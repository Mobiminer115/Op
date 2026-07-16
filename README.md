# GameBoost Universal 3.1

Theos tweak dành cho thiết bị iOS đã jailbreak. Một lần chạy GitHub Actions sẽ
build và kiểm tra ba artifact: rootful legacy, rootful hiện đại và rootless.

## Menu và cơ chế module

Menu có sidebar bên trái với ba mục:

- **GameBoost** có công tắc master riêng.
- **Enhance Graphic** có công tắc master riêng.
- **Settings** luôn hoạt động.

GameBoost và Enhance Graphic dùng chung một trạng thái module nên không thể bật
cùng lúc. Bật module này sẽ tắt module kia. Khi master của một module đang tắt,
toàn bộ vùng điều khiển của module đó vẫn hiển thị nhưng không nhận tương tác.
Cấu hình con không bị xóa, vì vậy lần bật sau vẫn giữ lựa chọn cũ.
App chưa từng có cấu hình sẽ khởi động với cả hai module tắt; cấu hình từ bản
1.x được tự chuyển sang GameBoost để không làm mất thiết lập cũ.

## GameBoost

- `Performance QoS`: ưu tiên thread gọi `CAMetalLayer.nextDrawable`. Tweak không
  còn tự tắt tính năng theo thông báo nhiệt. iOS vẫn có thể tự throttling để bảo
  vệ thiết bị; tweak không vô hiệu hóa cơ chế bảo vệ hệ thống.
- `Low latency 2-buffer`: giảm hàng đợi drawable Metal từ giá trị hiện tại xuống
  hai buffer. Có thể tắt riêng nếu một game bị khựng.
- `Giữ màn hình sáng`: tạm vô hiệu hóa idle timer và khôi phục trạng thái ban
  đầu khi GameBoost tắt.
- `Khóa ngang game`: giữ landscape ngay cả khi khóa xoay hệ thống đang bật.
- `FPS`: Auto, 30, 60 hoặc 120 cho `CADisplayLink` và `MTKView`; hệ thống tự
  giới hạn theo tần số tối đa của màn hình.
- `Độ phân giải app`: giảm backing resolution từ 100% xuống 10%, bước 5%, giữ
  nguyên logical bounds, tọa độ touch và tỉ lệ khung hình.

## Enhance Graphic

- `Super Resolution`: render backing framebuffer ở 100–150% rồi để compositor
  scale về màn hình.
- `Linear texture filter`: ưu tiên lọc tuyến tính trên sampler Metal.
- `Trilinear mip filter`: làm mượt chuyển mức mipmap trên sampler Metal.
- `Anisotropic filtering`: 1×, 2×, 4×, 8× hoặc 16×.
- `Display-P3 output`: đặt color space P3 cho `CAMetalLayer`.
- `High-quality layer scaling`: dùng trilinear khi thu nhỏ và linear khi phóng
  Metal layer.

Sampler dùng tọa độ không chuẩn hóa được giữ theo ràng buộc của Metal: min/mag
phải giống nhau, không dùng mipmap và anisotropy bằng 1. Điều này tránh tạo
descriptor không hợp lệ chỉ để cố ép chất lượng.

## Settings

- Kích thước menu 75–125% mà không dùng transform lên view của game.
- Cho phép kéo nút/menu hoặc tắt kéo để panel cố định chính giữa màn hình.
- Đổi màu chủ đề bằng hue slider.
- Đổi độ đậm của vật liệu kính 45–100%; không còn chỉnh `alpha` của cả panel nên
  màu tint, blur và chữ/điều khiển cập nhật độc lập.
- `Liquid Glass 26` dùng `UIGlassEffect` bằng runtime lookup trên hệ điều hành có
  API này. iOS 12–18 dùng material blur dự phòng với tint động, highlight chéo,
  viền phản quang và shadow mềm. Màu chủ đề chỉ làm accent thay vì phủ neon lên
  toàn bộ panel.

## Vì sao bỏ Device Spoof

Thử nghiệm thực tế cho thấy giả `UIDevice`/trait chỉ phóng to Roblox nhưng không
mở thêm slot hay leaderboard, vì các phần đó do logic riêng của client và từng
experience quyết định. Ép Metal framebuffer 4:3 trong PUBG lại kéo giãn surface
trên màn hình điện thoại thay vì đổi camera/FOV. Bản 3.1 gỡ toàn bộ hook spoof và
không còn sửa identity, trait hay tỉ lệ viewport của game.

## Thay đổi cần mở lại app

Game engine thường cache kích thước viewport và pipeline khi khởi động. Vì vậy
chuyển module hoặc thay đổi downscale/Super Resolution được lưu ngay nhưng chỉ
đổi framebuffer an toàn sau khi đóng hẳn rồi mở lại app.
Menu hiển thị ký hiệu `↻` khi đang chờ áp dụng. Filter sampler cũng chỉ tác động
chắc chắn tới pipeline được tạo sau khi module Enhance Graphic bật.

## Phạm vi hoạt động

`GameBoost.plist` lọc `com.apple.UIKit` để loader có thể đưa tweak vào app UIKit.
Trước khi cài hook, mã kiểm tra bundle và chỉ chạy trong tiến trình `.app` thông
thường; SpringBoard, extension, daemon và helper không tạo menu.

Các tính năng dùng API chung của UIKit, QuartzCore và Metal nên không phụ thuộc
Bundle ID. Tuy nhiên không có dylib chung nào có thể ép shader, texture pack,
MSAA hoặc setting nội bộ của mọi engine. Game tự viết renderer, OpenGL cũ hoặc
dynamic-resolution riêng có thể bỏ qua một phần thiết lập. Bản này không thêm
nút giả cho các chức năng không thể triển khai an toàn ở tầng hệ thống.

## Artifact

| Artifact                           | iOS     | Jailbreak | Kiến trúc         |
| ---------------------------------- | ------- | --------- | ----------------- |
| `gameboost-rootful-ios12-13-arm64` | 12–13.7 | rootful   | `arm64`           |
| `gameboost-rootful-ios14-18`       | 14–18   | rootful   | `arm64`, `arm64e` |
| `gameboost-rootless-ios15-18`      | 15–18   | rootless  | `arm64`, `arm64e` |

App/game thông thường dùng slice `arm64`, kể cả trên thiết bị A12 trở lên.
Binary hệ thống arm64e trên iOS 12–13 dùng ABI cũ và cần toolchain cũ riêng, nên
artifact legacy chỉ build `arm64`.

## Build trên GitHub

1. Đưa toàn bộ nội dung dự án vào root repository; giữ workflow tại
   `.github/workflows/makefile.yml`.
2. Xóa workflow YAML cũ bị lỗi nếu repository còn file khác trong
   `.github/workflows/`.
3. Mở **Actions → Build GameBoost Universal → Run workflow**.
4. Chờ cả ba matrix job xanh rồi tải artifact phù hợp thiết bị.

Workflow kiểm tra plist, source marker v3.1, kiến trúc dylib, framework liên kết và
đầu ra `.deb`/`.dylib`/`.plist`. Thiếu một điều kiện thì job dừng thay vì upload
artifact không đầy đủ.

Chỉ dùng trên thiết bị và ứng dụng mà bạn có quyền kiểm thử.
