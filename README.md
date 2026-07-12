# GameBoost Universal

Theos tweak dành cho thiết bị iOS đã jailbreak. Một lần chạy GitHub Actions sẽ
build ba artifact đã kiểm tra, gồm `.deb`, `GameBoost.dylib`, filter plist và
thông tin kiến trúc.

## Phạm vi hoạt động

`GameBoost.plist` dùng filter `com.apple.UIKit`, vì vậy tweak có thể được loader
đưa vào mọi tiến trình UIKit. Trước khi khởi tạo hook, `Tweak.xm` chỉ cho phép
chạy trong tiến trình `.app` thông thường và chặn SpringBoard. App extension,
daemon và helper process không khởi tạo menu hoặc hook.

## Chức năng

- Nút `GB` nổi, kéo được và bật/tắt panel.
- Cửa sổ trong suốt chỉ nhận touch tại nút/panel; phần còn lại trả touch cho app.
- `Performance QoS` nâng QoS của thread gọi `CAMetalLayer.nextDrawable`; tự tắt
  khi iOS báo trạng thái nhiệt `serious` hoặc `critical`.
- `Metal render scale` điều chỉnh `CAMetalLayer.drawableSize` từ 50% đến 150%,
  bước 5%. Mức 100% là kích thước gốc.

## Artifact

| Artifact | iOS | Jailbreak | Kiến trúc |
| --- | --- | --- | --- |
| `gameboost-rootful-ios12-13-arm64` | 12–13.7 | rootful | `arm64` |
| `gameboost-rootful-ios14-18` | 14–18 | rootful | `arm64`, `arm64e` |
| `gameboost-rootless-ios15-18` | 15–18 | rootless | `arm64`, `arm64e` |

App Store app/game thông thường dùng slice `arm64`, kể cả trên thiết bị A12 trở
lên. Binary hệ thống arm64e trên iOS 12–13 dùng ABI cũ và cần toolchain Xcode cũ
riêng, nên artifact legacy chỉ có `arm64`.

## Build một lần trên GitHub

1. Giải nén ZIP và đưa **nội dung bên trong thư mục `GameBoost`** vào root của
   repository. File workflow phải nằm đúng tại `.github/workflows/main.yml`.
2. Xóa workflow cũ khác trong `.github/workflows/` để không còn file YAML lỗi.
3. Mở **Actions → Build GameBoost Universal → Run workflow**.
4. Chờ ba matrix job hoàn tất, rồi lấy artifact phù hợp thiết bị.

Không cần nhập Bundle ID và không cần sửa plist. Workflow kiểm tra file nguồn,
filter `com.apple.UIKit`, kiến trúc dylib và các đầu ra `.deb`/dylib/plist; thiếu
bất kỳ đầu ra nào thì job sẽ dừng thay vì phát hành artifact lỗi.

## Giới hạn kỹ thuật

- iOS không cung cấp API user-space để ghim một app vào toàn bộ lõi CPU. Chế độ
  hiệu năng là QoS hint cho scheduler, không vô hiệu hóa quản lý nhiệt.
- Resolution scale áp dụng cho pipeline dùng `CAMetalLayer`. OpenGL hoặc engine
  có pipeline/dynamic-resolution riêng có thể cần hook riêng.
- Upscale trên 100% tăng tải GPU, nhiệt và pin; nó không phải MetalFX/FSR và
  không tự tạo thêm chi tiết hình ảnh.
- Chỉ dùng trên thiết bị/app mà bạn có quyền kiểm thử.
