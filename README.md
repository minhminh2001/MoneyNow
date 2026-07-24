# Loan App Firebase MVP

MVP app vay tiền online viết bằng **Flutter + Firebase**.

## Tổng quan nhanh

- App người vay: Flutter mobile
- Web admin: Flutter web, route `/admin`
- Backend: Firebase Auth, Firestore, Storage, Cloud Functions 2nd gen
- Firebase project hiện tại trong repo: `loan-a782e`
- Flutter version khóa theo repo: `3.41.6` trong `.fvmrc`
- Node.js yêu cầu cho `functions`: `20`

## Có gì trong project

- Đăng ký bằng **số điện thoại + OTP**, sau đó đăng nhập bằng **số điện thoại + mật khẩu**
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

## Yêu cầu môi trường

### Flutter

- Flutter SDK: `3.41.6`
- Dart SDK: theo Flutter 3.41.6
- Repo này có `.fvmrc`, nên nên dùng đúng Flutter version này

Nếu máy có nhiều Flutter version, ưu tiên chạy bằng:

```bash
/Users/noname/fvm/versions/3.41.6/bin/flutter --version
```

### Node.js

- Node.js: `20`
- Firebase CLI: bản mới

Ví dụ:

```bash
node -v
npm -v
firebase --version
```

### Firebase services cần bật

1. Authentication
2. Firestore Database
3. Firebase Storage
4. Cloud Functions
5. Nếu deploy web: Firebase Hosting

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

## Setup project lần đầu

### 1. Dùng đúng Flutter version

Repo đã có:

- `.fvmrc`
- `.fvm/version`

Nếu máy bạn có FVM:

```bash
fvm use 3.41.6
fvm flutter --version
```

Nếu không dùng FVM, gọi thẳng Flutter đúng version:

```bash
/Users/noname/fvm/versions/3.41.6/bin/flutter --version
```

### 2. Cài package Flutter

```bash
/Users/noname/fvm/versions/3.41.6/bin/flutter pub get
```

### 3. Cài package Functions

```bash
cd functions
npm install
npm run build
cd ..
```

## Setup Firebase

1. Tạo Firebase project mới
2. Bật:
   - Authentication > Phone
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

Lệnh này sẽ ghi lại file `lib/firebase_options.dart`.

### Firebase config hiện tại của repo

`firebase.json` hiện đang map tới project:

- `projectId`: `loan-a782e`

Platform app IDs hiện có:

- Android: `1:656565938424:android:9abc561ed0e4eb76bc730d`
- iOS: `1:656565938424:ios:1b17d6fd14f554f9bc730d`
- macOS: `1:656565938424:ios:1b17d6fd14f554f9bc730d`
- Web: `1:656565938424:web:e95b9cc999cd5ceabc730d`

Nếu đổi project Firebase, cần chạy lại:

```bash
flutterfire configure
```

## Cài backend Functions

```bash
cd functions
npm install
npm run build
cd ..
```

## Chạy local

### Chạy app Flutter thông thường

```bash
/Users/noname/fvm/versions/3.41.6/bin/flutter run
```

### Chạy web admin local

#### macOS / Linux

```bash
./scripts/run_admin_web.sh
```

#### PowerShell

```powershell
./scripts/run_admin_web.ps1
```

Script sẽ:

1. đọc version Flutter từ `.fvmrc`
2. dùng đúng SDK ở `$HOME/fvm/versions/<version>/bin/flutter`
3. chạy `flutter pub get`
4. mở thẳng route `/admin` trên Chrome

Nếu muốn chạy tay:

```bash
/Users/noname/fvm/versions/3.41.6/bin/flutter pub get
/Users/noname/fvm/versions/3.41.6/bin/flutter run -d chrome --web-launch-url "/admin"
```

### Chạy local với Emulator

```bash
firebase emulators:start
```

Trong app Flutter, bạn có thể nối emulator bằng cách tự thêm logic `useFirestoreEmulator`, `useAuthEmulator`, `useFunctionsEmulator` nếu muốn.

## Deploy

### Deploy riêng Functions

```bash
npx firebase-tools deploy --only functions
```

Hoặc:

```bash
cd functions
npm run build
cd ..
npx firebase-tools deploy --only functions
```

### Deploy toàn bộ Firebase resources

```bash
firebase deploy --only firestore,storage,functions
```

### Build web admin bản tĩnh

#### macOS / Linux

```bash
./scripts/build_admin_web.sh
```

#### PowerShell

```powershell
./scripts/build_admin_web.ps1
```

Script sẽ build web release bằng đúng Flutter version trong `.fvmrc`.

Output:

```text
build/web
```

### Build web release bằng lệnh tay

```bash
/Users/noname/fvm/versions/3.41.6/bin/flutter pub get
/Users/noname/fvm/versions/3.41.6/bin/flutter build web --release
```

### Nếu deploy web bằng Firebase Hosting

1. Build web:

```bash
./scripts/build_admin_web.sh
```

2. Thêm Hosting vào `firebase.json` nếu chưa có
3. Deploy:

```bash
npx firebase-tools deploy --only hosting
```

Lưu ý: repo hiện chưa cấu hình sẵn block `hosting` trong `firebase.json`, nên nếu muốn deploy web admin qua Firebase Hosting thì cần thêm cấu hình Hosting trước.

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

## Ghi nhớ: test OTP Firebase

Hiện tại project đang hỗ trợ test đăng nhập số điện thoại bằng `test phone numbers` của Firebase để dev trên iOS/debug mà chưa cần cấu hình APNs production đầy đủ.

### Cách dùng

1. Vào `Firebase Console` > `Authentication` > `Sign-in method`
2. Bật provider `Phone`
3. Mở mục `Phone numbers for testing`
4. Thêm một số test, ví dụ `+84901234567`
5. Gán mã OTP test, ví dụ `123456`
6. Chạy app bản debug và đăng nhập bằng đúng số test đó
7. Nhập đúng mã test đã khai báo, Firebase sẽ không gửi SMS thật

### Cấu hình đang dùng trong app

- Trong [main.dart](/Users/noname/Documents/loan_app_firebase_mvp/loan_app_firebase_mvp/lib/main.dart), bản debug đang bật:

```dart
FirebaseAuth.instance.setSettings(
  appVerificationDisabledForTesting: true,
);
```

- Trong [login_screen.dart](/Users/noname/Documents/loan_app_firebase_mvp/loan_app_firebase_mvp/lib/screens/auth/login_screen.dart), bản debug có banner nhắc đây là chế độ test OTP.

### Lưu ý rất quan trọng

- Khi `appVerificationDisabledForTesting = true`, chỉ số điện thoại test trong Firebase mới đăng nhập được
- Số điện thoại thật sẽ không hoàn tất OTP trong chế độ này
- Trước khi đưa sang production hoặc test OTP thật, phải tắt lại cờ test trong `lib/main.dart`
- Nếu muốn dùng OTP thật trên iOS, cần thêm APNs key trong Apple Developer và upload vào `Firebase Console` > `Project settings` > `Cloud Messaging`

### Lưu ý nền tảng test OTP

- OTP test mode hiện chỉ phù hợp cho Android/iOS debug
- Web admin không dùng luồng OTP này
- macOS native không phải luồng ưu tiên để test borrower auth

## Build iOS / TestFlight / APNs / Phone Auth

Phần này dùng khi chuẩn bị build iOS thật, upload lên `TestFlight`, hoặc setup production cho đăng nhập `Phone Auth`.

### Thông tin hiện tại của project

- Firebase project: `loan-a782e`
- Bundle ID iOS: `com.phanhoang.moneynow`
- Apple Team ID: `4M7L9447ZW`
- Flutter version khóa theo repo: `3.41.6`

### 1. Chuẩn bị môi trường local

Chạy đúng Flutter version của repo:

```bash
cd /Users/noname/Documents/loan_app_firebase_mvp/loan_app_firebase_mvp
fvm use 3.41.6
fvm flutter pub get
cd ios
pod install
cd ..
```

Nếu gặp lỗi pod/modulemap hoặc build cache iOS:

```bash
cd /Users/noname/Documents/loan_app_firebase_mvp/loan_app_firebase_mvp
fvm flutter clean
fvm flutter pub get
cd ios
pod install
cd ..
rm -rf ~/Library/Developer/Xcode/DerivedData/Runner-*
```

Nếu vẫn lỗi tiếp:

```bash
cd /Users/noname/Documents/loan_app_firebase_mvp/loan_app_firebase_mvp/ios
pod deintegrate
pod install
cd ..
```

### 2. Mở đúng workspace iOS

Luôn mở:

```bash
open ios/Runner.xcworkspace
```

Không archive từ `ios/Runner.xcodeproj`.

### 3. Signing và Capabilities bắt buộc cho iOS

Trong Xcode, vào `Runner` > `Signing & Capabilities` và kiểm tra:

- Team đúng: `4M7L9447ZW`
- Bundle Identifier đúng: `com.phanhoang.moneynow`
- Có `Push Notifications`
- Có `Background Modes`
- Trong `Background Modes` phải bật:
  - `Background fetch`
  - `Remote notifications`

### 4. APNs cho Firebase Phone Auth

Vì app dùng Firebase `Phone Auth`, iOS cần cấu hình APNs để silent push verification hoạt động ổn định trên thiết bị thật.

Checklist:

1. Vào Apple Developer
2. Tạo APNs auth key `.p8`
3. Lấy đúng:
   - `Key ID`
   - `Team ID`
4. Vào `Firebase Console` > `Project settings` > `Cloud Messaging`
5. Upload APNs auth key cho iOS app

Thông tin đã dùng trong project hiện tại:

- iOS app: `Money Now iOS`
- Bundle ID: `com.phanhoang.moneynow`
- Team ID: `4M7L9447ZW`

### 5. Phân biệt test OTP debug và OTP production

#### Debug test mode

Repo hiện hỗ trợ test bằng `Firebase test phone numbers`.

- Dùng được cho dev/debug
- Không gửi SMS thật
- Chỉ số test đã khai báo trong Firebase mới đăng nhập được

Trong debug, app có thể bật:

```dart
FirebaseAuth.instance.setSettings(
  appVerificationDisabledForTesting: true,
);
```

#### Production / TestFlight

Trước khi build bản đưa lên `TestFlight` hoặc production:

- tắt `appVerificationDisabledForTesting`
- không dùng số test để giả lập flow production
- test lại trên iPhone thật bằng số thật

### 6. Tăng version và build number trước khi upload

Kiểm tra `pubspec.yaml`:

```yaml
version: 1.0.1+2
```

Quy tắc:

- `1.0.1` là version hiển thị
- `2` là build number
- mỗi lần upload lên App Store Connect phải tăng build number

Ví dụ lần upload tiếp theo:

```yaml
version: 1.0.1+3
```

### 7. Test trên thiết bị thật trước khi archive

Nên test tối thiểu các luồng này trên iPhone thật:

1. Mở app thành công
2. Gửi OTP
3. Nhập OTP
4. Đăng ký xong sang bước tạo mật khẩu
5. Đăng nhập bằng số điện thoại + mật khẩu
6. Logout

Lưu ý:

- iOS simulator không phải luồng chuẩn để xác nhận OTP production
- Phone Auth trên iOS nên kiểm tra trên thiết bị thật

### 8. Archive và upload lên TestFlight

Trong Xcode:

1. Chọn target `Runner`
2. Chọn device `Any iOS Device (arm64)`
3. `Product` > `Clean Build Folder`
4. `Product` > `Archive`

Sau khi archive xong:

1. Mở `Organizer`
2. Chọn build mới tạo
3. `Distribute App`
4. Chọn `App Store Connect`
5. `Upload`

### 9. Sau khi upload

Sau khi upload thành công:

1. Vào `App Store Connect`
2. Chọn app
3. Vào tab `TestFlight`
4. Chờ Apple xử lý build
5. Add `Internal Testers` trước

Lưu ý:

- build không xuất hiện ngay lập tức
- build đầu tiên thường cần thêm thời gian để Apple xử lý
- external testers cần flow review riêng của TestFlight

### 10. Đổi tên app đúng chỗ

Nếu muốn đổi tên hiển thị trên iPhone:

- sửa `CFBundleDisplayName` trong `ios/Runner/Info.plist`

Nếu muốn đổi tên hiển thị trên App Store / TestFlight:

- vào `App Store Connect` > `App Information` > `Name`

Không nên phụ thuộc vào popup đổi tên trong Xcode onboarding nếu popup đó báo lỗi.

### 11. Checklist production cuối cùng

Trước khi gửi TestFlight, xác nhận lại:

- [ ] `fvm flutter pub get` chạy OK
- [ ] `pod install` chạy OK
- [ ] mở đúng `ios/Runner.xcworkspace`
- [ ] Team ID đúng
- [ ] Bundle ID đúng
- [ ] có `Push Notifications`
- [ ] có `Background Modes`
- [ ] đã bật `Background fetch`
- [ ] đã bật `Remote notifications`
- [ ] APNs key đã upload lên Firebase
- [ ] đã tắt `appVerificationDisabledForTesting`
- [ ] đã test gửi OTP trên iPhone thật
- [ ] đã tăng build number
- [ ] archive thành công
- [ ] upload thành công lên App Store Connect

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
7. Người dùng xem lịch thanh toán và thông tin chuyển khoản trả nợ ngay trong app

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

## App Store review package

Trước khi submit production lên App Store, chuẩn bị sẵn bộ thông tin này trong `App Store Connect` và `App Review Notes`.

### Metadata bắt buộc

- App name
- Subtitle
- Description
- Keywords
- Support URL
- Privacy Policy URL
- Marketing URL (nếu có)
- Ảnh screenshot đúng thiết bị
- App icon production

### Thông tin pháp lý và vận hành nên chuẩn bị

- Tên pháp nhân hoặc đơn vị vận hành dịch vụ tài chính
- Thông tin liên hệ hỗ trợ khách hàng
- Email hỗ trợ
- Số điện thoại hỗ trợ
- Website chính thức
- Chính sách riêng tư
- Điều khoản sử dụng
- Giải thích cách xử lý hồ sơ vay, tính phí, và thanh toán

### App Review Notes nên ghi rõ

1. App dùng Firebase Phone Auth để đăng nhập bằng số điện thoại + OTP
2. Reviewer nên test trên iPhone thật
3. Nếu app có tài khoản review riêng, cung cấp:
   - số điện thoại test
   - OTP test hoặc cách lấy OTP
   - mật khẩu nếu cần
4. Nếu một số luồng phụ thuộc backend, ghi rõ backend đã bật cho review
5. Giải thích ngắn gọn luồng người dùng:
   - đăng ký
   - xác minh OTP
   - tạo mật khẩu
   - cập nhật hồ sơ
   - tải tài liệu KYC
   - nộp hồ sơ vay
   - theo dõi khoản vay và lịch thanh toán
6. Nêu rõ app không thu tiền digital goods/in-app content nên không dùng In-App Purchase

### Lưu ý riêng cho bản production hiện tại

- Không để reviewer nhìn thấy tính năng mock hoặc nút test nội bộ
- Không để `appVerificationDisabledForTesting` chạy trong release
- Không yêu cầu reviewer dùng môi trường giả nếu production flow đã hoạt động
- Nếu app có role admin hoặc web admin riêng, ghi rõ đó không phải luồng người dùng cuối trên iOS

### Mẫu App Review Notes

```text
This app is a consumer finance application for account registration, profile verification, loan application submission, and repayment schedule tracking.

Review flow:
1. Sign up with phone number and OTP
2. Create password
3. Complete profile
4. Upload KYC documents
5. Submit loan application
6. Review loan details and repayment schedule

Important notes:
- Phone number authentication uses Firebase Phone Auth on iPhone.
- Please review on a physical iPhone device.
- Backend services are enabled and available during review.
- The app does not sell digital goods or digital subscriptions.
- Repayment status is updated by the operator/backend after transfer reconciliation; the iOS app does not expose internal testing or mock payment actions in production.

Reviewer account:
- Phone number: [fill here]
- OTP flow: [fill here]
- Password: [fill here if applicable]

Support:
- Support URL: [fill here]
- Privacy Policy URL: [fill here]
- Contact email: [minhvlkt.k56@gmail.com]
```
