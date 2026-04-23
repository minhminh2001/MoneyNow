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

Project zip này đã có toàn bộ code ứng dụng và backend Firebase, nhưng không kèm các runner folder native được sinh bởi Flutter SDK như `android/`, `ios/`, `web/`. Những thư mục đó cần được tạo từ máy local có cài Flutter.

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

## Chạy local với Emulator

```bash
firebase emulators:start
```

Trong app Flutter, bạn có thể nối emulator bằng cách tự thêm logic `useFirestoreEmulator`, `useAuthEmulator`, `useFunctionsEmulator` nếu muốn.

## Deploy

```bash
firebase deploy --only firestore,storage,functions
```

## Tài khoản admin và duyệt hồ sơ vay

Project hiện có màn hình duyệt hồ sơ vay ngay trong app. Chỉ tài khoản có `role = "admin"` mới nhìn thấy và sử dụng được khu vực này.

### Cách bật quyền admin cho một tài khoản

1. Đăng ký hoặc đăng nhập tài khoản cần dùng làm admin.
2. Mở Firebase Console.
3. Vào `Firestore Database`.
4. Mở collection `users`.
5. Chọn document có `uid` của tài khoản đó.
6. Thêm hoặc cập nhật field:

```json
{
  "role": "admin"
}
```

Sau khi cập nhật xong, hãy đăng xuất và đăng nhập lại app. Lúc này màn Home sẽ hiện thêm mục `Duyệt hồ sơ vay`.

### Cách hạ quyền admin

Đổi field `role` về:

```json
{
  "role": "user"
}
```

### Cách duyệt hồ sơ vay trong app

1. Đăng nhập bằng tài khoản admin.
2. Vào Home.
3. Chọn `Duyệt hồ sơ vay`.
4. Lọc danh sách theo `Chờ duyệt`, `Đã duyệt`, `Từ chối` hoặc `Tất cả`.
5. Chọn một hồ sơ và bấm:
   - `Duyệt`
   - `Từ chối`
   - `Chờ duyệt`

Khi bấm `Duyệt`, backend sẽ tự động:

- cập nhật `loanApplications.status = approved`
- ghi `approvedLoanId`
- tạo document trong `loans`
- tạo `loans/{loanId}/repaymentSchedules`
- cập nhật `users/{uid}.kycStatus = verified`

### Lưu ý

- Không cần tạo `functions/.env` cho chức năng admin này
- Backend duyệt tay sẽ kiểm tra `users/{uid}.role == "admin"`
- Sau khi thay đổi backend, hãy deploy lại Functions

```bash
cd functions
cmd /c npm install
cmd /c npm run build
firebase deploy --only functions
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
   - tính số tiền trả hàng tuần
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

## Trạng thái dữ liệu quan trọng

### Role người dùng

- `users/{uid}.role = "user"`: tài khoản người dùng thông thường
- `users/{uid}.role = "admin"`: được thấy và dùng màn `Duyệt hồ sơ vay`

### Trạng thái hồ sơ vay

- `reviewing`: hồ sơ đang được xem xét hoặc chờ thẩm định
- `approved`: hồ sơ đã được duyệt
- `rejected`: hồ sơ bị từ chối
- `pending` / `submitted`: vẫn được app xem là hồ sơ đang chờ duyệt

Lưu ý:

- Khi user đang có hồ sơ ở `reviewing`, `pending` hoặc `submitted`, app sẽ chặn tạo hồ sơ vay mới.
- Khi admin duyệt hồ sơ, backend sẽ tự tạo khoản vay và lịch trả nợ đi kèm.

### Trạng thái KYC của user

- `pending`: hồ sơ xác minh chưa đủ
- `submitted`: đã có dữ liệu/hồ sơ để tiếp tục xét duyệt
- `verified`: đã được duyệt và xác minh hoàn tất

### Trạng thái khoản vay

- `active`: khoản vay đang hoạt động
- `closed`: khoản vay đã tất toán
- `overdue`: khoản vay có kỳ trả nợ quá hạn

### Trạng thái kỳ trả nợ

- `unpaid`: chưa thanh toán
- `paid`: đã thanh toán
- `overdue`: đã quá hạn

## Rule chấm điểm mẫu

- Reject nếu thu nhập < 5 triệu
- Approve nếu:
  - đủ hồ sơ
  - amount <= monthlyIncome * 6
  - term trong khoảng 1-6 tuần
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
