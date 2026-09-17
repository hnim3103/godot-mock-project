# Hướng dẫn đọc Animation của nhân vật

Tài liệu này giải thích cách đọc / cắt / phát animation cho **mọi asset trong thư mục `sprites/`**.
Đọc hết mục 1 → 4 là đủ để tự làm; mục 5 là bảng tra cứu, mục 6 là các bẫy hay gặp.

> Một số nhân vật đóng gói khác hẳn (mỗi frame là 1 file PNG riêng, không có JSON) nên có tài liệu riêng:
> * Boss King Crab → [`boss/kingcrab/ANIMATION.md`](boss/kingcrab/ANIMATION.md)
> * Pelican → [`enemy/pelican/ANIMATION.md`](enemy/pelican/ANIMATION.md)

---

## 1. Trong `sprites/` có 3 kiểu đóng gói

Trước khi code, **mở thư mục ra xem có file gì** — sẽ rơi vào 1 trong 3 kiểu:

| Kiểu | Dấu hiệu nhận biết | Ví dụ | Cách đọc animation |
|---|---|---|---|
| **A. Sheet + JSON** | có cặp `*_sheet.png` + `*_sheet.json` trùng tên | `enemy/crab/` | Đọc `meta.frameTags` trong JSON → có sẵn tên + khoảng frame |
| **B. Sheet, không JSON** | chỉ có 1 file `*_sheet.png` | `enemy/mushroom/` | Tự chia lưới, tự đặt tên animation |
| **C. Mỗi frame 1 file PNG** | nhiều PNG đánh số `..._01.png`, `..._1.png` | `boss/kingcrab/`, `enemy/pelican/`, `object/*` | Đọc theo quy ước tên file (mục 4) |

Kiểu A là chuẩn nhất — **ưu tiên học kiểu A trước**, vì 2 kiểu còn lại chỉ là kiểu A bị thiếu metadata.

---

## 2. Kiểu A — Sprite sheet + JSON

File JSON là bản export của **Aseprite / LibreSprite** (format "Hash"). Nó có đúng 2 phần cần quan tâm:

```jsonc
{
  "frames": {
    "crab_sprite_sheet 0.png": {
      "frame": { "x": 0, "y": 0, "w": 192, "h": 64 },   // vùng cắt trên file PNG
      "duration": 100                                    // thời gian giữ frame này, ĐƠN VỊ: mili-giây
    },
    "crab_sprite_sheet 1.png": { "frame": { "x": 0, "y": 64, "w": 192, "h": 64 }, "duration": 100 },
    ...
  },
  "meta": {
    "size": { "w": 192, "h": 320 },                      // kích thước file PNG
    "frameTags": [                                        // <<< DANH SÁCH ANIMATION Ở ĐÂY
      { "name": "walk", "from": 0, "to": 2, "direction": "forward" },
      { "name": "hit",  "from": 3, "to": 4, "direction": "forward" }
    ]
  }
}
```

### 2.1. `frames` — danh sách frame theo thứ tự

* Mỗi phần tử = **1 frame animation**, theo đúng thứ tự xuất hiện trong file.
* Tên key có dạng `<tên> <index>.<đuôi>`, với `index` **bắt đầu từ 0** và khớp với thứ tự.
* `frame.x / frame.y / frame.w / frame.h` = hình chữ nhật cần cắt ra từ file PNG (gốc toạ độ ở **góc trên-trái**).

### 2.2. `meta.frameTags` — đây mới là "animation"

Mỗi tag là một animation hoàn chỉnh:

| Trường | Ý nghĩa |
|---|---|
| `name` | tên animation (`walk`, `idle`, `atk`, `hit`, ...) |
| `from` / `to` | chỉ số frame bắt đầu / kết thúc, **tính cả 2 đầu**, 0-based |
| `direction` | `forward` = chạy xuôi 0→n rồi quay lại đầu |

Ví dụ `crab`: `walk` = frame 0, 1, 2 (3 frame) — `hit` = frame 3, 4 (2 frame).

> **Nếu `frameTags` rỗng** (`war_lord_ulti`, `war_lord_walk`) → sheet đó chỉ có 1 animation duy nhất,
> dùng toàn bộ frame từ 0 đến hết.

### 2.3. `duration` — tốc độ, tính bằng **mili-giây / frame**

Đây là chỗ sinh viên hay sai nhất.

* `duration` nằm ở **từng frame**, **không phải** một FPS chung cho cả animation.
* `duration: 100` nghĩa là **giữ frame đó 100ms** (≈ 10 FPS), **không phải** 100 FPS.
* Công thức đổi sang FPS nếu cần: `fps = 1000 / duration`.
* Trong project này `duration` **thay đổi giữa các frame**, cố ý, để tạo nhịp. Đừng lấy giá trị của
  frame đầu rồi áp cho cả animation.

Vài ví dụ có thật trong project:

```
barrel / idle   : frame 0 = 1000ms, frame 1 = 200ms   → đứng yên lâu rồi giật một cái
aquaman / detect: frame 8 =  400ms, frame 9 = 300ms
aquaman / atk   : frame 10 = 200ms, frame 11 = 400ms  → ra đòn nhanh, giữ tư thế lâu
native  / atk   : 100, 100, 200, 300ms                → vung nhanh, đọng lại ở cuối
```

### 2.4. Cột trong sheet = **hướng nhân vật**

Nhìn `frame.w` và `frame.h`: nếu `w > h` thì **một "frame" trong JSON thực ra chứa nhiều hướng nằm cạnh nhau**.

```
Số hướng  =  frame.w / frame.h
Bề rộng 1 ô (cell)  =  frame.h
```

Kiểm chứng: `crab` 192 / 64 = **3 hướng**; `foxy` 256 / 64 = **4 cột**; `war_lord_walk` 384 / 128 = **3 hướng**;
`war_lord_idle_atk` 128 / 128 = **1 hướng** (sheet này chỉ có 1 hướng nhìn nghiêng).

**Quy ước cột dùng thống nhất trong cả project:**

| Cột | Hướng | Ghi chú |
|:---:|---|---|
| 0 | **xuống** (down) — quay mặt về phía camera | |
| 1 | **ngang** (side) — quay **sang TRÁI** | |
| 2 | **lên** (up) — quay lưng lại | |
| 3 | **ngang — quay sang PHẢI** | Chỉ `war_lord_defeat_sheet` có. Ở `foxy_*` cột 3 **trống hoàn toàn** (chừa chỗ, chưa dùng). |

→ Muốn nhân vật quay **sang phải**: lấy **cột 1** rồi **lật ngang** (`flipX` / `scale.x = -1`),
trừ khi sheet có sẵn cột 3.

**Công thức cắt 1 ô cụ thể:**

```
cellW = frame.h                    // ô luôn vuông: cellW = cellH = frame.h
srcX  = frame.x + dirIndex * cellW
srcY  = frame.y
srcW  = cellW
srcH  = frame.h
```

---

## 3. Kiểu B — Sheet nhưng KHÔNG có JSON

Gặp ở: `enemy/mushroom/mushroom_sprite_sheet.png`, `player/foxy_hat_sprite_sheet.png`,
`player/foxy_hat_actions_sprite_sheet.png`.

Cách xử lý:

1. **Xem sheet đó có "anh em song sinh" không.** Nếu có file cùng kích thước ở cùng thư mục đã có JSON
   thì **dùng chung JSON đó**:

   | Sheet không JSON | Dùng JSON của | Kích thước |
   |---|---|---|
   | `player/foxy_hat_sprite_sheet.png` | `player/foxy_sprite_sheet.json` | 256×960 (giống hệt) |
   | `player/foxy_hat_actions_sprite_sheet.png` | `player/foxy_actions_sprite_sheet.json` | 192×576 (giống hệt) |

   (`foxy_hat_*` là **skin thay thế** — vẫn là con cáo nhưng đội mũ cướp biển, khớp từng frame với
   `foxy_*`, không phải layer chồng lên.)

2. **Không có anh em → tự chia lưới.** Đoán `cellW = cellH` là một số chẵn đẹp (16/32/48/64/128),
   sao cho `sheetW % cellW == 0` và `sheetH % cellH == 0`, rồi mở ảnh ra soi mắt.

   Ví dụ `mushroom_sprite_sheet.png` là 144×288 → `cell = 48×48` → lưới **3 cột × 6 hàng**.
   3 cột = 3 hướng (theo quy ước mục 2.4), 6 hàng = 6 frame.

3. **Tự đặt duration.** Mặc định an toàn của project này là **100ms/frame**.

---

## 4. Kiểu C — Mỗi frame là một file PNG riêng

Không có metadata nào cả, **tên file chính là metadata**. Quy ước:

```
<tên đối tượng>_<tên action>_<số thứ tự>.png
```

Đọc như sau:

* **Cùng tiền tố, khác số cuối** → các frame của **cùng một animation**, chạy theo thứ tự số tăng dần.
* **Không có phần `<action>`** → đó là animation mặc định / duy nhất (thường là idle hoặc loop).
* **File không có số** → ảnh **tĩnh**, không animate (ví dụ `boat_body.png`, `flag/platform.png`, `palm_trunk.png`).
* Số có thể là `_1` hoặc `_01` — **không nhất quán giữa các thư mục**, phải sort theo **giá trị số**, không sort theo chuỗi
  (nếu không `_10` sẽ đứng trước `_2`).

> ### ⚠ Kiểu C chỉ có MỘT hướng, và hướng đó là **PHẢI**
> Khác với kiểu A (sheet có sẵn 3-4 cột hướng, cột nghiêng quay **trái** — xem mục 2.4), asset kiểu C
> chỉ được vẽ **một hướng duy nhất**, và trong project này là **quay/tấn công sang PHẢI**:
> King Crab vươn càng và lăn sang phải, Pelican có mỏ hướng sang phải.
> → Muốn quay sang trái thì **lật ngang** (`flipX` / `scale.x = -1`).
>
> Nghĩa là code lật hướng của 2 kiểu là **ngược nhau** — đừng dùng chung một hàm mà không kiểm tra.

Ví dụ đọc thực tế:

| Thư mục | File | Đọc ra là |
|---|---|---|
| `enemy/pelican` | `pelican_01..04` | `move` — bay lơ lửng, 4 frame, **100ms/frame**, loop |
| | `pelican_atk_01..03` | `atk` — há mỏ nhả đạn, 3 frame, **200ms/frame**, chạy 1 lần |
| | `pelican_bullet.png` | viên đạn (cầu gai), ảnh tĩnh |
| `object/ship_helm` | `ship_helm_idle_01..06` | idle 6 frame, loop |
| | `ship_helm_turn_01..04` | xoay vô-lăng 4 frame |
| `object/chest` | `chest_close_01..03` / `chest_open_01..05` | rương thường: đóng / mở |
| | `chest_gold_close_01..04` / `chest_gold_open_01..05` | rương vàng: đóng / mở |
| `object/boat` | `boat_body.png` + `boat_sail_1..5` | **ghép 2 lớp**: thân thuyền tĩnh + buồm động 5 frame |
| `object/flag` | `flag_01..05` + `platform.png` | cờ bay 5 frame + bệ tĩnh |
| `object/blade` | `blade_anim_1..5` / `blade_target_1..4` / `blade_throw_1` | 3 animation riêng của cùng 1 vật thể |
| `map/palm` | `palm_top_01..04` + `palm_trunk.png` | tán lá đung đưa 4 frame + thân cây tĩnh |

> ### ⚠ Số thứ tự KHÔNG phải lúc nào cũng là animation
> Trong `farm/`, `corn_01..04` **không phải** 4 frame của một animation mà là **4 giai đoạn lớn của cây**
> (mầm → trưởng thành → ra bắp). Dấu hiệu nhận biết: **kích thước file ảnh tăng dần**
> (`corn_01` 13×15 → `corn_04` 21×31). Animation thật thì **mọi frame luôn cùng kích thước**.
>
> Tương tự với `pumpkin_01..04`, `tomato_01..04`, `field_slot_01..04`.

---

## 5. Bảng tra cứu toàn bộ nhân vật

### 5.1. Có sẵn JSON (kiểu A)

| Asset | Sheet (px) | frame w×h | Ô | Số hướng | Animation (`tên` frame `from-to`) |
|---|---|---|:---:|:---:|---|
| `player/foxy_sprite_sheet` | 256×960 | 256×64 | 64 | 4 (cột 3 trống) | `walk` 0-3 · `idle` 4-5 · `hit` 6-8 · `jump` 9-10 · `atk` 11-14 |
| `player/foxy_actions_sprite_sheet` | 192×576 | 192×64 | 64 | 3 | `pushing` 0-4 · `carring` 5-8 |
| `enemy/crab` | 192×320 | 192×64 | 64 | 3 | `walk` 0-2 · `hit` 3-4 |
| `enemy/aquaman` | 192×1152 | 192×64 | 64 | 3 | `walk` 0-3 · `idle` 4-7 · `detect` 8-9 · `atk` 10-11 · `atk_idle` 12-15 · `hit` 16-17 |
| `enemy/barrel` | 192×576 | 192×64 | 64 | 3 | `idle` 0-1 · `atk` 2-6 · `hit` 7-8 |
| `enemy/native` | 192×832 | 192×64 | 64 | 3 | `walk` 0-3 · `hit` 4-6 · `atk` 7-10 · `suprise` 11-12 |
| `enemy/starfish` | 192×768 | 192×64 | 64 | 3 | `walk` 0-3 · `atk` 4-9 · `hit` 10-11 |
| `enemy/turtle` | 192×448 | 192×64 | 64 | 3 | `def` 0-4 · `walk` 5-6 |
| `boss/warlord/war_lord_walk` | 384×1024 | 384×128 | 128 | 3 | *(không tag)* — dùng cả 8 frame |
| `boss/warlord/war_lord_idle_atk` | 640×256 | 128×128 | 128 | 1 | `idle` 0-3 · `atk` 4-9 |
| `boss/warlord/war_lord_ulti` | 512×256 | 128×128 | 128 | 1 | *(không tag)* — dùng cả 8 frame |
| `object/stone/rock_01` | 256×128 | 32×32 | 32 | 1 | `down` 0-15 · `left` 16-31 |

Ghi chú:
* `aquaman` và `turtle` có thêm tag `Loop` **trùng khoảng frame với `walk`** — dùng `walk`, bỏ qua `Loop`.
* `native` ghi `suprise` (thiếu chữ `r` so với "surprise") — cứ dùng đúng tên trong file.
* `war_lord_idle_atk` và `war_lord_ulti` chỉ vẽ **1 hướng nhìn nghiêng** — lật ngang để đổi trái/phải.

### 5.2. Cần xử lý thủ công

| Asset | Vấn đề | Cách làm |
|---|---|---|
| `boss/warlord/war_lord_defeat_sheet` | JSON khai **1 frame duy nhất 512×1024** = cả tấm ảnh → **JSON không dùng được** | Tự chia lưới **128×128** → **4 cột × 8 hàng** = 8 frame × 4 hướng. Cột: 0=xuống, 1=trái, 2=lên, 3=phải |
| `enemy/mushroom` | không có JSON | Lưới 48×48 → 3 cột × 6 hàng |
| `player/foxy_hat_*` | không có JSON | Dùng JSON của `foxy_*` tương ứng (mục 3) |
| `boss/kingcrab` | 32 file PNG rời, không JSON | → [`boss/kingcrab/ANIMATION.md`](boss/kingcrab/ANIMATION.md) |
| `enemy/pelican` | 7 file PNG rời + 1 file đạn, không JSON | → [`enemy/pelican/ANIMATION.md`](enemy/pelican/ANIMATION.md) |

---

## 6. Các bẫy thường gặp

1. **`duration` là mili-giây, không phải FPS.** `100` = 100ms = 10 FPS. Xem lại mục 2.3.
2. **`duration` khác nhau giữa các frame.** Đừng lấy 1 giá trị áp cho cả animation.
3. **`from`/`to` tính cả 2 đầu.** `from: 0, to: 2` là **3 frame**, không phải 2.
4. **Một "frame" trong JSON ≠ một ô sprite** khi `frame.w > frame.h`. Phải chia tiếp theo cột hướng (mục 2.4).
5. **Thứ tự `frames` quan trọng, nhưng JSON object có thể bị đảo thứ tự khi parse** (tuỳ ngôn ngữ /
   thư viện). An toàn nhất: **sort theo con số ở cuối tên key** (`"... 0.png"`, `"... 1.png"`, ...),
   vì `frameTags.from/to` đánh chỉ số theo đúng thứ tự đó.
6. **Sort tên file kiểu C phải sort theo số**, không sort theo chuỗi — nếu không `_10` sẽ nhảy lên trước `_2`.
7. **Không có cột "quay phải"** ở hầu hết sheet → phải lật ngang cột 1.
8. **Kích thước frame tăng dần ⇒ đó là giai đoạn phát triển, không phải animation** (mục 4).
9. **Pixel art phải để filter = Point / Nearest**, tắt mipmap, tắt "compress texture" — nếu không sprite sẽ bị mờ.
