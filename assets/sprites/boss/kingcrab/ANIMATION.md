# King Crab — Hướng dẫn Animation

> Đọc [`sprites/ANIMATION_GUIDE.md`](../../ANIMATION_GUIDE.md) trước để nắm quy ước chung.
> King Crab là **kiểu C**: mỗi frame là **một file PNG riêng**, **không có file JSON**, nên toàn bộ
> thông tin animation nằm trong tài liệu này.

---

## 1. Thông số chung

| Mục | Giá trị |
|---|---|
| File | `King_Crab_1.png` … `King_Crab_32.png` (32 frame) |
| Kích thước mỗi frame | **128 × 128 px**, nền trong suốt, **tất cả frame bằng nhau** |
| Căn chỉnh | Mọi frame đã **căn sẵn cùng một gốc** → chỉ cần đổi texture, **không cần offset riêng cho từng frame** |
| Mặt đất (chân boss) | y ≈ **92** (frame `move` chạm đáy đúng y=92; frame lăn có bụi khói tràn xuống tới y≈95) |
| Pivot đề xuất | **(64, 92)** — giữa-đáy thân boss |
| Pivot của đạn (`bullet`) | **(64, 62)** — gần đúng tâm canvas |
| Hướng | Boss chỉ được vẽ ở **một hướng**: đòn đánh và cú lăn đều hướng sang **PHẢI**. Muốn boss tấn công sang trái → **lật ngang** (`flipX` / `scale.x = -1`) |

> ⚠ **Sort file theo số, không sort theo chuỗi.** Nếu sort chuỗi thì `King_Crab_10` sẽ nhảy lên
> đứng trước `King_Crab_2`. Phải parse số ở cuối tên file rồi sort theo giá trị số.

---

## 2. Bảng animation

Đây là spec gốc, giữ nguyên ký hiệu:

```
idle_atk : King_Crab_17-18                                                  (400ms/frame)
idle_stun: King_Crab_23-24-25-26                                            (50ms/frame)
move     : King_Crab_1-2-3-4                                                (200ms/frame)
hurt     :                                                                  (100ms/frame)
atk_1    : King_Crab_14-15 - [idle_atk] + [bullet] - 19 - 20-21-22 - [idle_stun] - 27-28
atk_2    : King_Crab_[5-6-7-8] - 9-10-11-12-13
bullet   : King_Crab_31-32
```

**Cách đọc ký hiệu:**

| Ký hiệu | Nghĩa |
|---|---|
| `a-b-c` | chạy lần lượt frame a → b → c |
| `[tên]` | **chèn nguyên một animation khác** vào giữa (dùng lại frame + tốc độ của animation đó) |
| `[5-6-7-8]` | **đoạn lặp** — lặp lại 5→6→7→8 cho tới khi trạng thái kết thúc |
| `+ [bullet]` | tại thời điểm này **sinh ra entity đạn** (không phải đổi frame của boss) |

### Bảng tổng hợp

| Animation | Frame | ms/frame | Lặp? | Ghi chú |
|---|---|:---:|---|---|
| `move` | 1 → 2 → 3 → 4 | **200** | Loop | Di chuyển |
| `idle_atk` | 17 ↔ 18 | **400** | Loop | Tư thế ngắm. Rất chậm (400ms) → cố ý tạo cảm giác "nén" trước khi bắn |
| `idle_stun` | 23 → 24 → 25 → 26 | **50** | Loop | Choáng. Rất nhanh (50ms) → sao quay tít |
| `hurt` | 29 → 30 | **100** | 1 lần (có thể lặp 2-3 vòng) | Trúng đòn — frame 29 là bản **flash sáng** của frame 30, xen kẽ để tạo nháy |
| `bullet` | 31 ↔ 32 | *(chưa quy định — đề xuất 100)* | Loop | Viên đạn |
| `atk_1` | *tổ hợp* | xem §3 | 1 lần | Bắn đạn bằng càng |
| `atk_2` | *tổ hợp* | xem §4 | 1 lần | Cuộn người lăn húc |

> **Ghi chú về `hurt`:** spec gốc chỉ ghi tốc độ `100ms/frame` mà **không liệt kê frame**.
> Frame 29 và 30 là 2 frame duy nhất còn lại chưa được dùng ở animation nào, và 29 đúng là
> bản flash của 30 → `hurt = 29-30`. Nếu artist có ý khác thì sửa lại dòng này.

> **Frame chưa dùng:** `King_Crab_16` **không xuất hiện trong spec**.
> Đây là frame dự phòng / chuyển tiếp — hiện không dùng.

---

## 3. `atk_1` — Bắn đạn bằng càng

```
14 → 15 → [idle_atk] → (+ spawn bullet) → 19 → 20 → 21 → 22 → [idle_stun] → 27 → 28
```

| Bước | Frame | ms/frame | Vai trò |
|:---:|---|:---:|---|
| 1 | 14 → 15 | *(đề xuất 100)* | Lấy đà |
| 2 | **`[idle_atk]`** = 17 ↔ 18 | **400** | Giữ tư thế ngắm — **cửa sổ để người chơi né** |
| 3 | **`+ [bullet]`** | — | **Sinh entity đạn** (frame 31-32), bắn về phía trước |
| 4 | 19 → 20 → 21 → 22 | *(đề xuất 100)* | Bắn + giật lùi |
| 5 | **`[idle_stun]`** = 23 → 26 | **50** | **Tự choáng sau khi bắn** — **cửa sổ phản công** của người chơi |
| 6 | 27 → 28 | *(đề xuất 100)* | Hồi phục, về tư thế đứng |

Sau bước 6 → quay về `move` / idle.

**Số vòng lặp của bước 2 và bước 5 là tham số gameplay**, không phải dữ liệu animation — tự chỉnh
trong code cho hợp độ khó (gợi ý khởi điểm: `idle_atk` 2-3 vòng ≈ 1.6-2.4s; `idle_stun` 10-20 vòng ≈ 2-4s).

---

## 4. `atk_2` — Cuộn người lăn húc

```
[5 → 6 → 7 → 8] (lặp) → 9 → 10 → 11 → 12 → 13
```

| Bước | Frame | ms/frame | Vai trò |
|:---:|---|:---:|---|
| 1 | **`[5-6-7-8]`** | *(đề xuất 100)* | **Đoạn lặp** — lặp suốt thời gian boss lao tới |
| 2 | 9 → 10 → 11 → 12 → 13 | *(đề xuất 100)* | Kết thúc cú lăn: tiếp đất → nhổm dậy → về tư thế đứng |

Số vòng lặp của bước 1 do **quãng đường lao** quyết định: cứ lặp `[5-6-7-8]` trong lúc boss còn di chuyển,
khi chạm mục tiêu / hết quãng đường thì chuyển sang bước 2.

---

## 5. Phần chưa có trong spec

Spec gốc chỉ ghi tốc độ cho `move`, `idle_atk`, `idle_stun`, `hurt`. Những chỗ sau **chưa được quy định**,
tài liệu này đang dùng **100ms/frame** (mặc định chung của project) — cần artist xác nhận:

* `atk_1` các frame `14-15`, `19-20-21-22`, `27-28`
* `atk_2` các frame `[5-6-7-8]` và `9-10-11-12-13`
* `bullet` frame `31-32`
* Danh sách frame của `hurt` (đang suy ra là `29-30`)
* Số vòng lặp mặc định của `[idle_atk]` và `[idle_stun]` trong `atk_1`

---

## 6. Gợi ý cấu hình trong code

Vì không có JSON, nên khai báo bảng animation ngay trong code / file config. Ví dụ:

```jsonc
{
  "frameSize": 128,
  "pivot":     { "x": 64, "y": 92 },
  "framePath": "sprites/boss/kingcrab/King_Crab_{n}.png",

  "animations": {
    "move":      { "frames": [1,2,3,4],     "ms": 200, "loop": true  },
    "idle_atk":  { "frames": [17,18],       "ms": 400, "loop": true  },
    "idle_stun": { "frames": [23,24,25,26], "ms": 50,  "loop": true  },
    "hurt":      { "frames": [29,30],       "ms": 100, "loop": false },
    "bullet":    { "frames": [31,32],       "ms": 100, "loop": true, "pivot": { "x": 64, "y": 62 } },

    // animation tổ hợp: chạy tuần tự các "đoạn"
    "atk_1": { "loop": false, "sequence": [
      { "frames": [14,15],        "ms": 100 },
      { "play": "idle_atk",       "repeat": 2 },
      { "spawn": "bullet" },
      { "frames": [19,20,21,22],  "ms": 100 },
      { "play": "idle_stun",      "repeat": 15 },
      { "frames": [27,28],        "ms": 100 }
    ]},

    "atk_2": { "loop": false, "sequence": [
      { "frames": [5,6,7,8],        "ms": 100, "repeatWhile": "isDashing" },
      { "frames": [9,10,11,12,13],  "ms": 100 }
    ]}
  }
}
```
