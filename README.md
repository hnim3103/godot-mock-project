# mock-project — Procedural Map & NavigationRegion3D

Dự án thử nghiệm Godot 3D với nhân vật dạng sprite, dùng để học cách tạo map và điều khiển NPC tìm đường.
Class được chọn cho bài trình bày với mentor là **`NavigationRegion3D`**.

## 1. Dự án hiện có gì?

- **Procedural map generation:** tạo nền, đường, gò đất, cầu thang, collision và marker spawn từ một seed.
- **Lưu map thành scene:** map được xuất thành `.tscn` để chỉnh sửa và sử dụng lại.
- **Navigation:** Main chứa `NavigationRegion3D` với navmesh đã bake cho map được chọn.
- **Movement NPC:** player đi tới một vị trí và nhấn **E**; NPC tìm đường tới vị trí đó rồi dừng gần đích.

Luồng sử dụng:

```text
Map Lab tạo map → Lưu scene → Đưa map vào Main → Bake navigation → Test movement
```

Generator chỉ sinh map và dữ liệu đánh dấu. Việc thiết lập navigation, spawn NPC và điều khiển nhân vật
thuộc scene gameplay. Chạy Main sẽ dùng map đã lưu, không tạo lại map mỗi lần chơi.

## 2. Test nhanh

### Điều khiển

| Phím | Tác dụng |
|---|---|
| WASD / phím mũi tên | Di chuyển player theo hướng camera |
| Space | Nhảy |
| E | Gửi vị trí hiện tại của player làm đích cho NPC đầu tiên trong `Enemies` |

Lệnh E chỉ được nhận khi player đang đứng trên sàn. NPC giữ nguyên đích đã chọn nếu player đi chỗ khác;
nhấn E lần nữa để đổi đích, kể cả khi NPC đang di chuyển. Action được code sử dụng là `npc_move_here`.

**Kết quả mong đợi:** NPC chỉ đi khi nhận lệnh, di chuyển theo đường navigation, có gravity và dừng gần đích.
Khoảng dừng hiện là `1.5` đơn vị để tránh cố đi xuyên vào collider của player.

Để xem navigation khi demo, bật **Debug → Visible Navigation**. Muốn xem đường của NPC, bật thêm
`Debug > Enabled` trên `NavigationAgent3D` trong scene Aquaman trước khi chạy.

## 3. File chính và kiểm tra

| File | Nội dung |
|---|---|
| [main.tscn](scenes/main.tscn) | Map đã lưu, region đã bake, player và spawner |
| [main.gd](scripts/main.gd) | Đặt player vào map và nhận lệnh E |
| [aquaman.gd](scenes/enemy/aquaman.gd) | `move_to()`, chờ navigation, đi theo path và dừng |


## 4. Giới hạn hiện tại

- NPC mới có movement theo lệnh; chưa có wandering, phát hiện player, combat hoặc chuyển animation idle/walk.
- Navmesh hiện có một đường vào cạnh cầu thang có thể khiến NPC bị kẹt.
- Map dùng mô hình mỗi ô X/Z có một mặt đứng; chưa hỗ trợ hang hoặc cầu với nhiều tầng chồng lên nhau.

## Ghi chú về việc sử dụng AI

Trong quá trình làm bài, có sử dụng AI (ChatGPT/Codex) hỗ trợ tìm hiểu API, lên kế hoạch,
viết và chỉnh sửa code, phân tích lỗi, xây dựng kiểm tra tự động và biên soạn tài liệu.
