# Loan App Firebase MVP

MVP app vay tiền online viết bằng **Flutter + Firebase**.

## Có gì trong project

- Đăng ký / đăng nhập bằng **Email + Password**
- Quản lý hồ sơ người dùng
- Upload hồ sơ KYC mẫu lên **Firebase Storage**
- Nộp hồ sơ vay qua **Cloud Functions**
- Tự động chấm sơ bộ, tạo khoản vay và lịch trả nợ mẫu
- Xem danh sách hồ sơ vay, khoản vay, kỳ thanh toán
- Mock thao tác thanh toán từng kỳ

## Cấu trúc chính

```text
lib/                    Flutter app
functions/              Cloud Functions 2nd gen (TypeScript)
firestore.rules         Quy tắc Firestore
storage.rules           Quy tắc Storage
firestore.indexes.json  Indexes Firestore
firebase.json           Cấu hình Firebase project
scripts/                Script bootstrap local
```

## Lưu ý quan trọng

Project zip này đã có **toàn bộ code ứng dụng và backend Firebase**, nhưng **không kèm các runner folder native được sinh bởi Flutter SDK** (`android/`, `ios/`, `web/`), vì những thư mục đó phải được tạo từ máy local có cài Flutter.  
Sau khi giải nén, chỉ cần chạy:

### macOS / Linux / Git Bash
```bash
./scripts/bootstrap_flutter_project.sh
```

### PowerShell
```powershell
./scripts/bootstrap_flutter_project.ps1
```

Script trên sẽ:
1. tạo một project Flutter tạm bằng `flutter create`
2. copy các thư mục native runner (`android/`, `ios/`, `web/`, `.metadata`) vào project hiện tại
3. chạy `flutter pub get`

## Setup Firebase

1. Tạo Firebase project mới
2. Bật:
   - Authentication > Email/Password
   - Firestore Database
   - Firebase Storage
   - Cloud Functions
3. Chọn project bằng Firebase CLI:
   ```bash
   firebase login
   firebase use --add
   ```
4. Cài FlutterFire CLI:
   ```bash
   dart pub global activate flutterfire_cli
   ```
5. Generate file Firebase config:
   ```bash
   flutterfire configure
   ```
   Lệnh này sẽ ghi đè file `lib/firebase_options.dart` placeholder trong project.

## Cài backend Functions

```bash
cd functions
npm install
npm run build
cd ..
```

## Chạy local với Emulator (khuyên dùng)

```bash
firebase emulators:start
```

Trong app Flutter, bạn có thể nối emulator bằng cách tự thêm logic `useFirestoreEmulator`, `useAuthEmulator`, `useFunctionsEmulator` nếu muốn.

## Deploy

```bash
firebase deploy --only firestore,storage,functions
```

## Chạy app

```bash
flutter run
```

## Luồng nghiệp vụ mẫu

1. Đăng ký tài khoản
2. Cập nhật hồ sơ
3. Upload 3 ảnh KYC:
   - CCCD mặt trước
   - CCCD mặt sau
   - Selfie cầm CCCD
4. Tạo yêu cầu vay
5. Cloud Function `submitLoanApplication` sẽ:
   - kiểm tra hồ sơ
   - kiểm tra tài liệu
   - tính số tiền trả hàng tháng
   - auto approve / reviewing / reject theo rule mẫu
6. Nếu approved:
   - tạo `loans/{loanId}`
   - tạo subcollection `repaymentSchedules`
7. Người dùng có thể mock thanh toán từng kỳ bằng `markRepaymentPaidMock`

## Collection layout

```text
users/{uid}
users/{uid}/documents/{docId}

loanApplications/{applicationId}

loans/{loanId}
loans/{loanId}/repaymentSchedules/{scheduleId}
```

## Rule chấm điểm mẫu

- Reject nếu thu nhập < 5 triệu
- Approve nếu:
  - đủ hồ sơ
  - amount <= monthlyIncome * 6
  - term trong khoảng 3-12 tháng
- Reviewing nếu:
  - đủ hồ sơ
  - amount <= monthlyIncome * 8
- Reject các case còn lại

## Production checklist

Đây là MVP demo. Để lên production, nên bổ sung:

- OTP phone auth
- eKYC provider thật
- mã hóa dữ liệu nhạy cảm
- admin dashboard riêng
- audit logs đầy đủ
- payment gateway thật
- push notification
- fraud/risk engine
- App Check
- phân quyền vận hành
