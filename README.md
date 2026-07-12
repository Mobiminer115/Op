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
- `Độ phân giải app` giảm backing resolution từ 100% xuống 50%, bước 5%,
  nhưng giữ nguyên `UIScreen.bounds`, kích thước UI và tỉ lệ khung hình. Tweak
  không dùng `transform`, vì vậy không phóng/zoom nội dung.
- Mức mới được lưu ngay và có ký hiệu `↻`; đóng rồi mở lại app để áp dụng. Việc
  áp dụng từ lúc app khởi động tránh lỗi viewport cũ gây crop/zoom ở các engine
  cache framebuffer.
- Với MetalKit, thay đổi đi qua `MTKView.drawableSize` để engine nhận callback
  đổi kích thước và cập nhật viewport. `CAMetalLayer` tùy biến cũng được đồng bộ
  theo kích thước layer. Menu GameBoost vẫn render ở độ phân giải gốc.

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
- Tweak đồng bộ các metric pixel của `UIScreen`, backing scale của UIKit,
  `MTKView` và `CAMetalLayer`. Logical bounds/tọa độ cảm ứng không thay đổi.
- Renderer không dựa trên UIKit/Metal hoặc engine có pipeline/dynamic-resolution
  riêng vẫn có thể bỏ qua thiết lập này.
- Đây là giảm số pixel render để nhẹ GPU, không phải MetalFX/FSR và không tạo
  thêm chi tiết hình ảnh.
- Chỉ dùng trên thiết bị/app mà bạn có quyền kiểm thử.
