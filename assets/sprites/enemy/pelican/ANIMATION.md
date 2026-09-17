# Pelican — Hướng dẫn Animation

> Đọc [`sprites/ANIMATION_GUIDE.md`](../../ANIMATION_GUIDE.md) trước để nắm quy ước chung.
> Pelican là **kiểu C**: mỗi frame là **một file PNG riêng**, **không có file JSON**, nên toàn bộ
> thông tin animation nằm trong tài liệu này.

---

## 1. Thông số chung

| Mục | Giá trị |
|---|---|
| File nhân vật | `pelican_01.png` … `pelican_04.png`, `pelican_atk_01.png` … `pelican_atk_03.png` (7 frame) |
| File đạn | `pelican_bullet.png` |
| Kích thước frame nhân vật | **48 × 48 px**, nền trong suốt, **tất cả frame bằng nhau** |
| Kích thước đạn | **24 × 24 px** |
| Căn chỉnh | Mọi frame đã **căn sẵn cùng một gốc** → chỉ cần đổi texture, **không cần offset riêng cho từng frame** |
| Pivot đề xuất | **(24, 24)** — tâm canvas. Pelican là quái **bay**, không có đường chạm đất |
| Pivot của đạn | **(12, 12)** — tâm canvas đạn |
| Hướng | Pelican được vẽ ở **một hướng: quay mặt sang PHẢI**. Muốn bay/tấn công sang trái → **lật ngang** (`flipX` / `scale.x = -1`) |

> ⚠ Số thứ tự ở đây dùng dạng **2 chữ số** (`_01`, `_02`) — khác với King Crab dùng `_1`, `_2`.
> Vẫn nên sort theo **giá trị số** chứ đừng sort theo chuỗi, để code dùng lại được cho cả 2 bộ.

---

## 2. Bảng animation

Spec gốc:

```
move: fps: 100ms/frame   pelican_01-02-03-04
atk : fps: 200ms/frame   pelican_atk_01-02-03
```

| Animation | Frame | ms/frame | Lặp? | Tổng thời lượng | Ghi chú |
|---|---|:---:|---|:---:|---|
| `move` | `pelican_01` → `02` → `03` → `04` | **100** | Loop | 400ms/vòng | Bay lơ lửng — biên độ nhấp nhô chỉ **2px**, cố ý nhỏ |
| `atk` | `pelican_atk_01` → `02` → `03` | **200** | 1 lần | 600ms | Há mỏ nhả đạn. Xong thì quay về `move` |
| `bullet` | `pelican_bullet.png` | — | — | — | **Ảnh tĩnh 1 frame**, không có animation |

Vòng lặp `move` khép kín (`04` → `01` liền mạch), **không cần ping-pong** — cứ chạy `forward` rồi quay về đầu.

> Bộ asset này **không có animation `idle` riêng**. Nếu game cần trạng thái đứng yên thì dùng lại
> `move` — cần xác nhận với artist.

---

## 3. Phần chưa có trong spec

* **Đạn sinh ra ở frame nào?** Chưa quy định. `pelican_atk_03` là khung nhả mạnh nhất
  → đề xuất **spawn `pelican_bullet` khi vào `atk_03`**. Cần artist xác nhận.
* **Vị trí spawn đạn** (đầu mỏ) — chưa quy định.
* **Có `hurt` / `die` không?** Trong thư mục **không có** frame nào cho 2 trạng thái này.
  Nếu game cần, tạm dùng cách nháy màu (tint trắng/đỏ) trên frame `move` hiện tại.
* **`pelican_bullet` có xoay không?** File chỉ có 1 frame. Nếu muốn đạn quay thì xoay bằng
  transform (`rotation`) lúc chạy, không có frame thứ 2 để lật.

---

## 4. Gợi ý cấu hình trong code

```jsonc
{
  "frameSize": 48,
  "pivot":     { "x": 24, "y": 24 },
  "facing":    "right",                 // lat ngang de bay/ban sang trai

  "animations": {
    "move": {
      "frames": ["pelican_01", "pelican_02", "pelican_03", "pelican_04"],
      "ms": 100, "loop": true
    },
    "atk": {
      "frames": ["pelican_atk_01", "pelican_atk_02", "pelican_atk_03"],
      "ms": 200, "loop": false,
      "events": [
        { "onFrame": "pelican_atk_03", "spawn": "bullet" }   // can xac nhan
      ]
    },
    "bullet": {
      "frames": ["pelican_bullet"],
      "static": true,
      "size": 24, "pivot": { "x": 12, "y": 12 }
    }
  }
}
```
