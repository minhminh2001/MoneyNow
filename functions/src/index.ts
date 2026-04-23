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

const REQUIRED_DOCUMENT_TYPES = ["id_front", "id_back", "selfie"] as const;
const FIXED_INTEREST_RATE = 0.08;
const MAX_TERM_WEEKS = 6;
const OVERDUE_PENALTY_FEE = 50000;
const PENDING_APPLICATION_STATUSES = ["reviewing", "pending", "submitted"] as const;

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
  const totalInterest = Math.round(amount * FIXED_INTEREST_RATE);
  const totalPayable = amount + totalInterest;
  const weeklyInstallment = Math.round(totalPayable / termWeeks);
  return {
    totalInterest,
    totalPayable,
    weeklyInstallment,
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
}) {
  const {applicationRef, application, now} = params;
  const loanRef = db.collection("loans").doc();
  const loanId = loanRef.id;
  const amount = Number(application.amount ?? 0);
  const termWeeks = Number(application.termWeeks ?? 0);
  const weeklyInstallment = Number(application.weeklyInstallment ?? 0);
  const totalInterest = Number(application.totalInterest ?? 0);
  const totalPayable = Number(application.totalPayable ?? 0);
  const interestRate = Number(application.interestRate ?? FIXED_INTEREST_RATE);
  const overduePenaltyFee = Number(application.overduePenaltyFee ?? OVERDUE_PENALTY_FEE);
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
    termWeeks,
    purpose,
    monthlyIncome,
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

export const reviewLoanApplicationManual = onCall(async (request: any) => {
  const payload = (request.data ?? {}) as Partial<ManualReviewLoanApplicationPayload>;
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
      "Chi tai khoan admin moi co quyen duyet ho so vay.",
    );
  }

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
