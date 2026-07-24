import * as admin from "firebase-admin";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { setGlobalOptions } from "firebase-functions/v2";

admin.initializeApp();
const db = admin.firestore();

setGlobalOptions({
  region: "asia-southeast1",
  maxInstances: 10,
});

type SubmitLoanApplicationPayload = {
  amount: number;
  termWeeks: number;
  purpose: string;
};

type ManualReviewLoanApplicationPayload = {
  applicationId: string;
  decision: "approved" | "rejected" | "reviewing";
  decisionReason?: string;
};

type AdminPaymentSettings = {
  repaymentAccountHolder: string;
  repaymentBankName: string;
  repaymentAccountNumber: string;
  updatedBy: string;
  updatedAt: number | null;
};

function serializeTimestamp(value: unknown): number | null {
  if (!value) return null;
  if (value instanceof admin.firestore.Timestamp) {
    return value.toMillis();
  }
  if (value instanceof Date) {
    return value.getTime();
  }
  if (typeof value === "number") {
    return value;
  }
  return null;
}

function serializeDocument(
  id: string,
  data: FirebaseFirestore.DocumentData,
): Record<string, unknown> {
  return {
    id,
    ...data,
    createdAt: serializeTimestamp(data.createdAt),
    updatedAt: serializeTimestamp(data.updatedAt),
    approvedAt: serializeTimestamp(data.approvedAt),
    nextDueDate: serializeTimestamp(data.nextDueDate),
    contactsSyncedAt: serializeTimestamp(data.contactsSyncedAt),
  };
}

async function requireAdminUidFromRequest(request: any): Promise<string> {
  let reviewerUid = request.auth?.uid as string | undefined;
  if (!reviewerUid) {
    const idToken = String(request.data?.idToken ?? "").trim();
    if (!idToken) {
      throw new HttpsError("unauthenticated", "Ban can dang nhap.");
    }

    try {
      const decoded = await admin.auth().verifyIdToken(idToken);
      reviewerUid = decoded.uid;
    } catch (_error) {
      throw new HttpsError("unauthenticated", "Phien dang nhap khong hop le.");
    }
  }

  const reviewerSnap = await db.collection("users").doc(reviewerUid).get();
  const reviewerRole = String(reviewerSnap.get("role") ?? "").trim().toLowerCase();
  if (reviewerRole !== "admin") {
    throw new HttpsError(
      "permission-denied",
      "Chi tai khoan admin moi co quyen truy cap khu vuc nay.",
    );
  }

  return reviewerUid;
}

async function requireSignedInUidFromRequest(request: any): Promise<string> {
  let uid = request.auth?.uid as string | undefined;
  if (uid) return uid;

  const idToken = String(request.data?.idToken ?? "").trim();
  if (!idToken) {
    throw new HttpsError("unauthenticated", "Ban can dang nhap.");
  }

  try {
    const decoded = await admin.auth().verifyIdToken(idToken);
    return decoded.uid;
  } catch (_error) {
    throw new HttpsError("unauthenticated", "Phien dang nhap khong hop le.");
  }
}

async function deleteCollectionDocs(
  collectionRef: FirebaseFirestore.CollectionReference,
): Promise<number> {
  const snapshot = await collectionRef.get();
  if (snapshot.empty) return 0;

  const writer = db.bulkWriter();
  snapshot.docs.forEach((doc) => writer.delete(doc.ref));
  await writer.close();
  return snapshot.size;
}

async function deleteLoanWithSchedules(loanDoc: FirebaseFirestore.QueryDocumentSnapshot): Promise<void> {
  await deleteCollectionDocs(loanDoc.ref.collection("repaymentSchedules"));
  await loanDoc.ref.delete();
}

async function performAccountDeletion(uid: string): Promise<{
  deletedLoanApplications: number;
  deletedLoans: number;
}> {
  try {
    const bucket = admin.storage().bucket();
    await bucket.deleteFiles({
      prefix: `users/${uid}/documents/`,
      force: true,
    });
  } catch (error) {
    console.warn(`Failed to delete storage files for ${uid}`, error);
  }

  const userRef = db.collection("users").doc(uid);
  const [loanApplicationsSnap, loansSnap] = await Promise.all([
    db.collection("loanApplications").where("uid", "==", uid).get(),
    db.collection("loans").where("uid", "==", uid).get(),
  ]);

  await Promise.all([
    deleteCollectionDocs(userRef.collection("documents")),
    deleteCollectionDocs(userRef.collection("phoneContacts")),
    ...loansSnap.docs.map((doc) => deleteLoanWithSchedules(doc)),
  ]);

  const writer = db.bulkWriter();
  loanApplicationsSnap.docs.forEach((doc) => writer.delete(doc.ref));
  writer.delete(userRef);
  writer.delete(db.collection("accountDeletionRequests").doc(uid));
  await writer.close();

  await admin.auth().deleteUser(uid);

  return {
    deletedLoanApplications: loanApplicationsSnap.size,
    deletedLoans: loansSnap.size,
  };
}

const REQUIRED_DOCUMENT_TYPES = ["id_front", "id_back", "selfie"] as const;
const INSURANCE_DOCUMENT_TYPES = ["insurance_proof"] as const;
const FIXED_INTEREST_RATE = 0.08;
const APPRAISAL_FEE_RATE = 0.04;
const SERVICE_FEE_RATE = 0.04;
const MAX_TERM_WEEKS = 6;
const OVERDUE_PENALTY_FEE = 50000;
const PENDING_APPLICATION_STATUSES = ["reviewing", "pending", "submitted"] as const;

function adminPaymentSettingsRef() {
  return db.collection("adminConfigs").doc("paymentSettings");
}

function assertNumber(value: unknown, fieldName: string): number {
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed <= 0) {
    throw new HttpsError("invalid-argument", `${fieldName} khong hop le.`);
  }
  return parsed;
}

function addDays(baseDate: Date, days: number): Date {
  return new Date(
    baseDate.getFullYear(),
    baseDate.getMonth(),
    baseDate.getDate() + days,
    9,
    0,
    0,
    0,
  );
}

function calculateWeeklyLoanTerms(amount: number, termWeeks: number) {
  const appraisalFee = Math.round(amount * APPRAISAL_FEE_RATE);
  const serviceFee = Math.round(amount * SERVICE_FEE_RATE);
  const netDisbursement = Math.round(amount - appraisalFee - serviceFee);
  const totalInterest = Math.round(amount * FIXED_INTEREST_RATE);
  const totalPayable = amount + totalInterest;
  const weeklyInstallment = Math.round(totalPayable / termWeeks);
  return {
    appraisalFee,
    serviceFee,
    netDisbursement,
    totalInterest,
    totalPayable,
    weeklyInstallment,
  };
}

async function fetchRepaymentProfileForAdmin(adminUid?: string) {
  const configSnap = await adminPaymentSettingsRef().get();
  if (configSnap.exists) {
    const config = configSnap.data() ?? {};
    return {
      repaymentAccountHolder: String(config.repaymentAccountHolder ?? ""),
      repaymentBankName: String(config.repaymentBankName ?? ""),
      repaymentAccountNumber: String(config.repaymentAccountNumber ?? ""),
    };
  }

  if (adminUid) {
    const adminSnap = await db.collection("users").doc(adminUid).get();
    const adminData = adminSnap.data() ?? {};
    return {
      repaymentAccountHolder: String(adminData.repaymentAccountHolder ?? ""),
      repaymentBankName: String(adminData.repaymentBankName ?? ""),
      repaymentAccountNumber: String(adminData.repaymentAccountNumber ?? ""),
    };
  }

  const adminSnap = await db
    .collection("users")
    .where("role", "==", "admin")
    .limit(1)
    .get();
  const adminData = adminSnap.empty ? {} : (adminSnap.docs[0].data() ?? {});
  return {
    repaymentAccountHolder: String(adminData.repaymentAccountHolder ?? ""),
    repaymentBankName: String(adminData.repaymentBankName ?? ""),
    repaymentAccountNumber: String(adminData.repaymentAccountNumber ?? ""),
  };
}

async function fetchAdminPaymentSettingsRecord(adminUid: string): Promise<AdminPaymentSettings> {
  const configSnap = await adminPaymentSettingsRef().get();
  if (configSnap.exists) {
    const config = configSnap.data() ?? {};
    return {
      repaymentAccountHolder: String(config.repaymentAccountHolder ?? ""),
      repaymentBankName: String(config.repaymentBankName ?? ""),
      repaymentAccountNumber: String(config.repaymentAccountNumber ?? ""),
      updatedBy: String(config.updatedBy ?? ""),
      updatedAt: serializeTimestamp(config.updatedAt),
    };
  }

  const fallback = await fetchRepaymentProfileForAdmin(adminUid);
  return {
    ...fallback,
    updatedBy: "",
    updatedAt: null,
  };
}

function buildWeeklyRepaymentSchedule(amount: number, termWeeks: number) {
  const totalInterest = Math.round(amount * FIXED_INTEREST_RATE);
  const basePrincipalAmount = Math.floor(amount / termWeeks);
  const baseInterestAmount = Math.floor(totalInterest / termWeeks);
  let remainingPrincipal = amount;
  let remainingInterest = totalInterest;

  return Array.from({ length: termWeeks }, (_, index) => {
    const installmentNo = index + 1;
    const principalAmount =
      installmentNo === termWeeks ? remainingPrincipal : basePrincipalAmount;
    const interestAmount =
      installmentNo === termWeeks ? remainingInterest : baseInterestAmount;
    const openingBalance = remainingPrincipal;
    const closingBalance = Math.max(0, openingBalance - principalAmount);
    const amountDue = principalAmount + interestAmount;

    remainingPrincipal = closingBalance;
    remainingInterest = Math.max(0, remainingInterest - interestAmount);

    return {
      installmentNo,
      amount: amountDue,
      principalAmount,
      interestAmount,
      openingBalance,
      closingBalance,
      overduePenaltyFee: OVERDUE_PENALTY_FEE,
    };
  });
}

function normalizeManualDecision(value: unknown): "approved" | "rejected" | "reviewing" {
  const decision = String(value ?? "").trim().toLowerCase();
  if (decision === "approved" || decision === "rejected" || decision === "reviewing") {
    return decision;
  }
  throw new HttpsError(
    "invalid-argument",
    "decision phai la approved, rejected hoac reviewing.",
  );
}

async function createApprovedLoanArtifacts(params: {
  applicationRef: admin.firestore.DocumentReference;
  application: FirebaseFirestore.DocumentData;
  now: admin.firestore.FieldValue;
  repaymentProfile?: {
    repaymentAccountHolder: string;
    repaymentBankName: string;
    repaymentAccountNumber: string;
  };
}) {
  const {applicationRef, application, now, repaymentProfile} = params;
  const loanRef = db.collection("loans").doc();
  const loanId = loanRef.id;
  const amount = Number(application.amount ?? 0);
  const termWeeks = Number(application.termWeeks ?? 0);
  const weeklyInstallment = Number(application.weeklyInstallment ?? 0);
  const totalInterest = Number(application.totalInterest ?? 0);
  const totalPayable = Number(application.totalPayable ?? 0);
  const interestRate = Number(application.interestRate ?? FIXED_INTEREST_RATE);
  const overduePenaltyFee = Number(application.overduePenaltyFee ?? OVERDUE_PENALTY_FEE);
  const appraisalFee = Number(application.appraisalFee ?? Math.round(amount * APPRAISAL_FEE_RATE));
  const serviceFee = Number(application.serviceFee ?? Math.round(amount * SERVICE_FEE_RATE));
  const netDisbursement =
    Number(application.netDisbursement ?? Math.round(amount - appraisalFee - serviceFee));
  const startDate = new Date();
  const batch = db.batch();

  batch.update(applicationRef, {
    status: "approved",
    approvedLoanId: loanId,
    updatedAt: now,
  });

  batch.set(loanRef, {
    uid: String(application.uid ?? ""),
    applicationId: applicationRef.id,
    principal: amount,
    appraisalFee,
    serviceFee,
    netDisbursement,
    borrowerPayoutAccountHolder: String(application.borrowerPayoutAccountHolder ?? ""),
    borrowerPayoutBankName: String(application.borrowerPayoutBankName ?? ""),
    borrowerPayoutAccountNumber: String(application.borrowerPayoutAccountNumber ?? ""),
    repaymentAccountHolder: String(repaymentProfile?.repaymentAccountHolder ?? ""),
    repaymentBankName: String(repaymentProfile?.repaymentBankName ?? ""),
    repaymentAccountNumber: String(repaymentProfile?.repaymentAccountNumber ?? ""),
    repaymentTransferNote: `TRA NO ${loanId}`,
    interestRate,
    termWeeks,
    weeklyInstallment,
    totalInterest,
    totalPayable,
    overduePenaltyFee,
    status: "active",
    nextDueDate: addDays(startDate, 7),
    createdAt: now,
    approvedAt: now,
  });

  for (const installment of buildWeeklyRepaymentSchedule(amount, termWeeks)) {
    const scheduleRef = loanRef.collection("repaymentSchedules").doc();
    batch.set(scheduleRef, {
      loanId,
      installmentNo: installment.installmentNo,
      dueDate: addDays(startDate, installment.installmentNo * 7),
      amount: installment.amount,
      principalAmount: installment.principalAmount,
      interestAmount: installment.interestAmount,
      openingBalance: installment.openingBalance,
      closingBalance: installment.closingBalance,
      overduePenaltyFee: installment.overduePenaltyFee,
      lateFeeAmount: 0,
      totalDue: installment.amount,
      paidAmount: 0,
      status: "unpaid",
      paidAt: null,
      createdAt: now,
      updatedAt: now,
    });
  }

  await batch.commit();
  return loanId;
}

export const submitLoanApplication = onCall(async (request: any) => {
  let uid = request.auth?.uid as string | undefined;
  if (!uid) {
    const idToken = String(request.data?.idToken ?? "").trim();
    if (!idToken) {
      throw new HttpsError("unauthenticated", "Ban can dang nhap.");
    }

    try {
      const decoded = await admin.auth().verifyIdToken(idToken);
      uid = decoded.uid;
    } catch (_error) {
      throw new HttpsError("unauthenticated", "Phien dang nhap khong hop le.");
    }
  }

  const payload = (request.data ?? {}) as Partial<SubmitLoanApplicationPayload>;

  const amount = assertNumber(payload.amount, "amount");
  const termWeeks = Math.round(assertNumber(payload.termWeeks, "termWeeks"));
  const purpose = String(payload.purpose ?? "").trim();

  if (purpose.length === 0) {
    throw new HttpsError("invalid-argument", "purpose khong duoc de trong.");
  }

  if (termWeeks < 1 || termWeeks > MAX_TERM_WEEKS) {
    throw new HttpsError("invalid-argument", "Ky han vay phai tu 1 den 6 tuan.");
  }

  const userRef = db.collection("users").doc(uid);
  const [userSnap, documentSnap] = await Promise.all([
    userRef.get(),
    userRef.collection("documents").get(),
  ]);

  if (!userSnap.exists) {
    throw new HttpsError("failed-precondition", "Ban can cap nhat ho so truoc.");
  }

  const user = userSnap.data() ?? {};
  const monthlyIncome = Number(user.monthlyIncome ?? 0);
  const insuranceNumber = String(user.insuranceNumber ?? "").trim();
  const borrowerPayoutAccountHolder = String(user.payoutAccountHolder ?? "").trim();
  const borrowerPayoutBankName = String(user.payoutBankName ?? "").trim();
  const borrowerPayoutAccountNumber = String(user.payoutAccountNumber ?? "").trim();
  const profileComplete = Boolean(
    user.fullName && user.phone && user.address && user.nationalId,
  );

  if (!profileComplete) {
    throw new HttpsError(
      "failed-precondition",
      "Ho so chua day du. Vui long cap nhat ho ten, SDT, dia chi va CCCD.",
    );
  }

  const uploadedTypes = new Set(
    documentSnap.docs.map((doc: any) => String(doc.get("type"))),
  );
  if (!insuranceNumber) {
    throw new HttpsError(
      "failed-precondition",
      "Ban can nhap so bao hiem truoc khi nop ho so vay.",
    );
  }
  const missingDocs = REQUIRED_DOCUMENT_TYPES.filter((type) => !uploadedTypes.has(type));
  const pendingApplicationSnap = await db
    .collection("loanApplications")
    .where("uid", "==", uid)
    .where("status", "in", [...PENDING_APPLICATION_STATUSES])
    .limit(1)
    .get();

  if (!pendingApplicationSnap.empty) {
    throw new HttpsError(
      "failed-precondition",
      "Bạn đang có hồ sơ vay chờ duyệt. Vui lòng đợi kết quả của hồ sơ hiện tại trước khi tạo hồ sơ mới.",
    );
  }

  const applicationRef = db.collection("loanApplications").doc();
  const {
    appraisalFee,
    serviceFee,
    netDisbursement,
    totalInterest,
    totalPayable,
    weeklyInstallment,
  } = calculateWeeklyLoanTerms(amount, termWeeks);

  let status: "approved" | "reviewing" | "rejected" = "reviewing";
  let decisionReason = "Ho so dang duoc tham dinh.";
  let riskLevel: "low" | "medium" | "high" = "medium";

  if (monthlyIncome < 5000000) {
    status = "rejected";
    decisionReason = "Thu nhap toi thieu cho MVP nay la 5.000.000 VND/thang.";
    riskLevel = "high";
  } else if (missingDocs.length > 0) {
    status = "rejected";
    decisionReason = `Ho so bi thieu tai lieu: ${missingDocs.join(", ")}.`;
    riskLevel = "high";
  } else if (amount <= monthlyIncome * 4) {
    status = "approved";
    decisionReason = "Ho so dat nguong auto-approve muc rui ro thap.";
    riskLevel = "low";
  } else if (amount <= monthlyIncome * 6 && termWeeks <= MAX_TERM_WEEKS) {
    status = "approved";
    decisionReason = "Ho so dat nguong auto-approve.";
    riskLevel = "medium";
  } else if (amount <= monthlyIncome * 8) {
    status = "reviewing";
    decisionReason = "Ho so can them buoc tham dinh thu cong.";
    riskLevel = "high";
  } else {
    status = "rejected";
    decisionReason = "So tien vay vuot nguong duoc phep cua MVP.";
    riskLevel = "high";
  }

  const batch = db.batch();
  const now = admin.firestore.FieldValue.serverTimestamp();

  const applicationData = {
    uid,
    amount,
    appraisalFee,
    serviceFee,
    netDisbursement,
    termWeeks,
    purpose,
    monthlyIncome,
    borrowerPayoutAccountHolder,
    borrowerPayoutBankName,
    borrowerPayoutAccountNumber,
    weeklyInstallment,
    interestRate: FIXED_INTEREST_RATE,
    totalInterest,
    totalPayable,
    overduePenaltyFee: OVERDUE_PENALTY_FEE,
    status,
    decisionReason,
    riskLevel,
    approvedLoanId: null as string | null,
    createdAt: now,
    updatedAt: now,
  };

  batch.set(applicationRef, applicationData);

  let loanId: string | null = null;

  if (status === "approved") {
    const repaymentProfile = await fetchRepaymentProfileForAdmin();
    const loanRef = db.collection("loans").doc();
    loanId = loanRef.id;
    const startDate = new Date();

    batch.update(applicationRef, {
      approvedLoanId: loanId,
      updatedAt: now,
    });

    batch.set(loanRef, {
      uid,
      applicationId: applicationRef.id,
      principal: amount,
      appraisalFee,
      serviceFee,
      netDisbursement,
      borrowerPayoutAccountHolder,
      borrowerPayoutBankName,
      borrowerPayoutAccountNumber,
      repaymentAccountHolder: repaymentProfile.repaymentAccountHolder,
      repaymentBankName: repaymentProfile.repaymentBankName,
      repaymentAccountNumber: repaymentProfile.repaymentAccountNumber,
      repaymentTransferNote: `TRA NO ${loanId}`,
      interestRate: FIXED_INTEREST_RATE,
      termWeeks,
      weeklyInstallment,
      totalInterest,
      totalPayable,
      overduePenaltyFee: OVERDUE_PENALTY_FEE,
      status: "active",
      nextDueDate: addDays(startDate, 7),
      createdAt: now,
      approvedAt: now,
    });

    for (const installment of buildWeeklyRepaymentSchedule(amount, termWeeks)) {
      const scheduleRef = loanRef.collection("repaymentSchedules").doc();
      batch.set(scheduleRef, {
        loanId: loanId,
        installmentNo: installment.installmentNo,
        dueDate: addDays(startDate, installment.installmentNo * 7),
        amount: installment.amount,
        principalAmount: installment.principalAmount,
        interestAmount: installment.interestAmount,
        openingBalance: installment.openingBalance,
        closingBalance: installment.closingBalance,
        overduePenaltyFee: installment.overduePenaltyFee,
        lateFeeAmount: 0,
        totalDue: installment.amount,
        paidAmount: 0,
        status: "unpaid",
        paidAt: null,
        createdAt: now,
        updatedAt: now,
      });
    }
  }

  if (missingDocs.length === 0) {
    batch.set(
      userRef,
      {
        kycStatus: status === "approved" ? "verified" : "submitted",
        updatedAt: now,
      },
      { merge: true },
    );
  }

  await batch.commit();

  return {
    applicationId: applicationRef.id,
    loanId,
    status,
    message: decisionReason,
  };
});

export const markRepaymentPaidMock = onCall(async (request: any) => {
  let uid = request.auth?.uid as string | undefined;
  if (!uid) {
    const idToken = String(request.data?.idToken ?? "").trim();
    if (!idToken) {
      throw new HttpsError("unauthenticated", "Ban can dang nhap.");
    }

    try {
      const decoded = await admin.auth().verifyIdToken(idToken);
      uid = decoded.uid;
    } catch (_error) {
      throw new HttpsError("unauthenticated", "Phien dang nhap khong hop le.");
    }
  }

  const loanId = String(request.data?.loanId ?? "");
  const scheduleId = String(request.data?.scheduleId ?? "");

  if (!loanId || !scheduleId) {
    throw new HttpsError("invalid-argument", "loanId va scheduleId la bat buoc.");
  }

  const loanRef = db.collection("loans").doc(loanId);
  const scheduleRef = loanRef.collection("repaymentSchedules").doc(scheduleId);

  await db.runTransaction(async (transaction: any) => {
    const [loanSnap, scheduleSnap] = await Promise.all([
      transaction.get(loanRef),
      transaction.get(scheduleRef),
    ]);

    if (!loanSnap.exists) {
      throw new HttpsError("not-found", "Khong tim thay khoan vay.");
    }

    if (!scheduleSnap.exists) {
      throw new HttpsError("not-found", "Khong tim thay ky thanh toan.");
    }

    const loan = loanSnap.data() ?? {};
    if (loan.uid !== uid) {
      throw new HttpsError("permission-denied", "Ban khong co quyen.");
    }

    const schedule = scheduleSnap.data() ?? {};
    if (schedule.status === "paid") {
      return;
    }

    transaction.update(scheduleRef, {
      status: "paid",
      paidAmount: Number(schedule.totalDue ?? schedule.amount ?? 0),
      paidAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });

  const remainingSchedules = await loanRef
    .collection("repaymentSchedules")
    .orderBy("installmentNo", "asc")
    .get();

  const unpaid = remainingSchedules.docs
    .map((doc: any) => ({ id: doc.id, ...doc.data() }))
    .filter((item: any) => item.status !== "paid");

  await loanRef.set(
    {
      status: unpaid.length === 0 ? "closed" : "active",
      nextDueDate: unpaid.length === 0 ? null : unpaid[0].dueDate,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true },
  );

  return {
    ok: true,
    remainingInstallments: unpaid.length,
  };
});

export const requestAccountDeletion = onCall(async (request: any) => {
  const uid = await requireSignedInUidFromRequest(request);

  const [userSnap, loanApplicationsSnap, loansSnap] = await Promise.all([
    db.collection("users").doc(uid).get(),
    db.collection("loanApplications").where("uid", "==", uid).get(),
    db.collection("loans").where("uid", "==", uid).get(),
  ]);

  const user = userSnap.data() ?? {};
  const activeLoanCount = loansSnap.docs.filter((doc) => {
    const status = String(doc.get("status") ?? "").trim().toLowerCase();
    return status === "active" || status === "overdue";
  }).length;

  await db.collection("accountDeletionRequests").doc(uid).set(
    {
      uid,
      status: "pending",
      fullName: String(user.fullName ?? ""),
      phone: String(user.phone ?? ""),
      email: String(user.email ?? ""),
      activeLoanCount,
      loanCount: loansSnap.size,
      applicationCount: loanApplicationsSnap.size,
      requestedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true },
  );

  return {
    ok: true,
    status: "pending",
    activeLoanCount,
    loanCount: loansSnap.size,
    applicationCount: loanApplicationsSnap.size,
  };
});

export const fetchAccountDeletionRequests = onCall(async (request: any) => {
  await requireAdminUidFromRequest(request);

  const snapshot = await db
    .collection("accountDeletionRequests")
    .orderBy("requestedAt", "desc")
    .limit(100)
    .get();

  return {
    requests: snapshot.docs.map((doc) => serializeDocument(doc.id, doc.data())),
  };
});

export const rejectAccountDeletionRequest = onCall(async (request: any) => {
  const adminUid = await requireAdminUidFromRequest(request);
  const uid = String(request.data?.uid ?? "").trim();
  const reason = String(request.data?.reason ?? "").trim();

  if (!uid) {
    throw new HttpsError("invalid-argument", "uid la bat buoc.");
  }

  await db.collection("accountDeletionRequests").doc(uid).set(
    {
      status: "rejected",
      rejectedBy: adminUid,
      rejectedAt: admin.firestore.FieldValue.serverTimestamp(),
      rejectionReason: reason,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true },
  );

  return { ok: true };
});

export const approveAccountDeletionRequest = onCall(async (request: any) => {
  const adminUid = await requireAdminUidFromRequest(request);
  const uid = String(request.data?.uid ?? "").trim();

  if (!uid) {
    throw new HttpsError("invalid-argument", "uid la bat buoc.");
  }

  const requestRef = db.collection("accountDeletionRequests").doc(uid);
  await requestRef.set(
    {
      status: "processing",
      approvedBy: adminUid,
      approvedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true },
  );

  const result = await performAccountDeletion(uid);
  return { ok: true, ...result };
});

export const fetchAdminDashboard = onCall(async (request: any) => {
  await requireAdminUidFromRequest(request);

  const [applicationsSnap, loansSnap, usersSnap] = await Promise.all([
    db.collection("loanApplications").orderBy("createdAt", "desc").limit(200).get(),
    db.collection("loans").orderBy("createdAt", "desc").limit(200).get(),
    db.collection("users").where("role", "==", "admin").limit(20).get(),
  ]);

  const applications = applicationsSnap.docs.map((doc) =>
    serializeDocument(doc.id, doc.data()),
  );
  const loans = loansSnap.docs.map((doc) => serializeDocument(doc.id, doc.data()));

  const neededUids = new Set<string>();
  for (const application of applications) {
    const uid = String(application.uid ?? "").trim();
    if (uid) neededUids.add(uid);
  }
  for (const loan of loans) {
    const uid = String(loan.uid ?? "").trim();
    if (uid) neededUids.add(uid);
  }

  const userDocs = await Promise.all(
    [...neededUids].map((uid) => db.collection("users").doc(uid).get()),
  );

  const userSummaries: Record<string, Record<string, unknown>> = {};
  for (const userDoc of userDocs) {
    if (!userDoc.exists) continue;
    const data = userDoc.data() ?? {};
    userSummaries[userDoc.id] = {
      uid: userDoc.id,
      fullName: String(data.fullName ?? ""),
      email: String(data.email ?? ""),
      phone: String(data.phone ?? ""),
      role: String(data.role ?? ""),
      kycStatus: String(data.kycStatus ?? ""),
    };
  }

  return {
    ok: true,
    applications,
    loans,
    userSummaries,
    adminCount: usersSnap.size,
  };
});

export const fetchAdminPaymentSettings = onCall(async (request: any) => {
  const adminUid = await requireAdminUidFromRequest(request);
  return fetchAdminPaymentSettingsRecord(adminUid);
});

export const saveAdminPaymentSettings = onCall(async (request: any) => {
  const adminUid = await requireAdminUidFromRequest(request);
  const repaymentAccountHolder = String(request.data?.repaymentAccountHolder ?? "").trim();
  const repaymentBankName = String(request.data?.repaymentBankName ?? "").trim();
  const repaymentAccountNumber = String(request.data?.repaymentAccountNumber ?? "").trim();

  if (!repaymentAccountHolder || !repaymentBankName || !repaymentAccountNumber) {
    throw new HttpsError(
      "invalid-argument",
      "Thong tin chu tai khoan, ngan hang va so tai khoan la bat buoc.",
    );
  }

  const adminSnap = await db.collection("users").doc(adminUid).get();
  const adminData = adminSnap.data() ?? {};
  const updatedBy = String(
    adminData.fullName ?? adminData.phone ?? adminData.email ?? adminUid,
  ).trim();
  const now = admin.firestore.FieldValue.serverTimestamp();

  await adminPaymentSettingsRef().set(
    {
      repaymentAccountHolder,
      repaymentBankName,
      repaymentAccountNumber,
      updatedBy,
      updatedByUid: adminUid,
      updatedAt: now,
    },
    {merge: true},
  );

  return fetchAdminPaymentSettingsRecord(adminUid);
});

export const reviewLoanApplicationManual = onCall(async (request: any) => {
  const payload = (request.data ?? {}) as Partial<ManualReviewLoanApplicationPayload>;
  const reviewerUid = await requireAdminUidFromRequest(request);

  const applicationId = String(payload.applicationId ?? "").trim();
  const decision = normalizeManualDecision(payload.decision);
  const decisionReason = String(payload.decisionReason ?? "").trim();

  if (!applicationId) {
    throw new HttpsError("invalid-argument", "applicationId la bat buoc.");
  }

  const applicationRef = db.collection("loanApplications").doc(applicationId);
  const applicationSnap = await applicationRef.get();

  if (!applicationSnap.exists) {
    throw new HttpsError("not-found", "Khong tim thay ho so vay.");
  }

  const application = applicationSnap.data() ?? {};
  const applicantUid = String(application.uid ?? "").trim();
  if (!applicantUid) {
    throw new HttpsError("failed-precondition", "Ho so vay khong co uid hop le.");
  }

  const now = admin.firestore.FieldValue.serverTimestamp();
  const resolvedReason =
    decisionReason ||
    (decision === "approved"
      ? "Hồ sơ đã được duyệt thủ công."
      : decision === "rejected"
        ? "Hồ sơ chưa được chấp thuận sau khi thẩm định thủ công."
        : "Hồ sơ đang được thẩm định thủ công.");

  if (decision === "approved") {
    const amount = Number(application.amount ?? 0);
    const termWeeks = Number(application.termWeeks ?? 0);
    if (amount <= 0 || termWeeks <= 0) {
      throw new HttpsError("failed-precondition", "Ho so vay dang thieu du lieu de phe duyet.");
    }

    const existingApprovedLoanId = String(application.approvedLoanId ?? "").trim();
    if (existingApprovedLoanId) {
      throw new HttpsError(
        "failed-precondition",
        "Ho so nay da duoc duyet truoc do va da co khoan vay di kem.",
      );
    }

    await applicationRef.set(
      {
        decisionReason: resolvedReason,
        updatedAt: now,
      },
      {merge: true},
    );

    const loanId = await createApprovedLoanArtifacts({
      applicationRef,
      application,
      now,
      repaymentProfile: await fetchRepaymentProfileForAdmin(reviewerUid),
    });

    await db.collection("users").doc(applicantUid).set(
      {
        kycStatus: "verified",
        updatedAt: now,
      },
      {merge: true},
    );

    return {
      ok: true,
      applicationId,
      loanId,
      status: "approved",
      message: resolvedReason,
    };
  }

  if (String(application.approvedLoanId ?? "").trim()) {
    throw new HttpsError(
      "failed-precondition",
      "Ho so nay da co khoan vay duoc tao. Khong the chuyen ve rejected hoac reviewing.",
    );
  }

  await applicationRef.set(
    {
      status: decision,
      decisionReason: resolvedReason,
      updatedAt: now,
    },
    {merge: true},
  );

  await db.collection("users").doc(applicantUid).set(
    {
      kycStatus: "submitted",
      updatedAt: now,
    },
    {merge: true},
  );

  return {
    ok: true,
    applicationId,
    loanId: null,
    status: decision,
    message: resolvedReason,
  };
});

export const syncOverdueLoans = onSchedule(
  {
    schedule: "every day 01:00",
    timeZone: "Asia/Bangkok",
    region: "asia-southeast1",
  },
  async (_event) => {
    const loanSnap = await db.collection("loans").where("status", "==", "active").get();
    const now = new Date();
    const batch = db.batch();
    let touched = 0;

    for (const loanDoc of loanSnap.docs) {
      const scheduleSnap = await loanDoc.ref
        .collection("repaymentSchedules")
        .where("status", "==", "unpaid")
        .get();

      let foundOverdue = false;

      for (const scheduleDoc of scheduleSnap.docs) {
        const dueDate = scheduleDoc.get("dueDate")?.toDate?.();
        if (dueDate instanceof Date && dueDate.getTime() < now.getTime()) {
          const lateFeeAmount = Number(scheduleDoc.get("lateFeeAmount") ?? 0);
          const overduePenaltyFee = Number(
            scheduleDoc.get("overduePenaltyFee") ?? OVERDUE_PENALTY_FEE,
          );
          const amount = Number(scheduleDoc.get("amount") ?? 0);
          batch.update(scheduleDoc.ref, {
            status: "overdue",
            lateFeeAmount: lateFeeAmount > 0 ? lateFeeAmount : overduePenaltyFee,
            totalDue: amount + (lateFeeAmount > 0 ? lateFeeAmount : overduePenaltyFee),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
          foundOverdue = true;
          touched += 1;
        }
      }

      if (foundOverdue) {
        batch.update(loanDoc.ref, {
          status: "overdue",
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
    }

    if (touched > 0) {
      await batch.commit();
    }

    return;
  },
);
