# Codex macOS Database App Planning Pack

Gói này gồm:

- `MASTER_PROMPT.md`: Prompt yêu cầu Codex khảo sát repository và lập kế hoạch xây dựng ứng dụng quản trị cơ sở dữ liệu native cho macOS.
- `AGENTS.md`: Bộ rules áp dụng xuyên suốt repository.

## Cách sử dụng

1. Copy `AGENTS.md` vào thư mục gốc của repository.
2. Mở Codex tại repository đó.
3. Gửi toàn bộ nội dung trong `MASTER_PROMPT.md`.
4. Yêu cầu Codex chỉ lập kế hoạch trong lần chạy đầu tiên.
5. Review tài liệu trong `docs/` trước khi cho phép triển khai production code.

## Kiến trúc mặc định

- Swift + SwiftUI + AppKit cho macOS UI.
- Rust cho database core và các tác vụ nặng.
- SQLite cho metadata không nhạy cảm.
- macOS Keychain cho secrets.
- Phân phối trực tiếp bằng Developer ID được ưu tiên để giảm hạn chế của App Sandbox.
