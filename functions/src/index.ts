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
  termMonths: number;
  purpose: string;
};

const REQUIRED_DOCUMENT_TYPES = ["id_front", "id_back", "selfie"] as const;
const FLAT_MONTHLY_INTEREST_RATE = 0.018;

function assertNumber(value: unknown, fieldName: string): number {
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed <= 0) {
    throw new HttpsError("invalid-argument", `${fieldName} khong hop le.`);
  }
  return parsed;
}

function addMonths(baseDate: Date, months: number): Date {
  return new Date(
    baseDate.getFullYear(),
    baseDate.getMonth() + months,
    baseDate.getDate(),
    9,
    0,
    0,
    0,
  );
}

function calculateMonthlyInstallment(amount: number, termMonths: number): number {
  const totalPayable = amount * (1 + FLAT_MONTHLY_INTEREST_RATE * termMonths);
  return Math.round(totalPayable / termMonths);
}

export const submitLoanApplication = onCall(async (request: any) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Ban can dang nhap.");
  }

  const uid = request.auth.uid;
  const payload = (request.data ?? {}) as Partial<SubmitLoanApplicationPayload>;

  const amount = assertNumber(payload.amount, "amount");
  const termMonths = Math.round(assertNumber(payload.termMonths, "termMonths"));
  const purpose = String(payload.purpose ?? "").trim();

  if (purpose.length === 0) {
    throw new HttpsError("invalid-argument", "purpose khong duoc de trong.");
  }

  if (termMonths < 3 || termMonths > 24) {
    throw new HttpsError("invalid-argument", "Ky han vay phai tu 3 den 24 thang.");
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

  const applicationRef = db.collection("loanApplications").doc();
  const monthlyInstallment = calculateMonthlyInstallment(amount, termMonths);

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
  } else if (amount <= monthlyIncome * 6 && termMonths >= 3 && termMonths <= 12) {
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
    termMonths,
    purpose,
    monthlyIncome,
    monthlyInstallment,
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
      interestRateMonthly: FLAT_MONTHLY_INTEREST_RATE,
      termMonths,
      monthlyInstallment,
      status: "active",
      nextDueDate: addMonths(startDate, 1),
      createdAt: now,
      approvedAt: now,
    });

    for (let installmentNo = 1; installmentNo <= termMonths; installmentNo += 1) {
      const scheduleRef = loanRef.collection("repaymentSchedules").doc();
      batch.set(scheduleRef, {
        loanId: loanId,
        installmentNo,
        dueDate: addMonths(startDate, installmentNo),
        amount: monthlyInstallment,
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
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Ban can dang nhap.");
  }

  const uid = request.auth.uid;
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
      paidAmount: Number(schedule.amount ?? 0),
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

export const syncOverdueLoans = onSchedule(
  {
    schedule: "every day 01:00",
    timeZone: "Asia/Bangkok",
    region: "asia-southeast1",
  },
  async () => {
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
          batch.update(scheduleDoc.ref, {
            status: "overdue",
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

    return null;
  },
);
