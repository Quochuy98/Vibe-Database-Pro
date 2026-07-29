# AGENTS.md

## 1. Purpose

Repository này chứa một ứng dụng quản trị cơ sở dữ liệu native cho macOS.

Mọi agent làm việc trong repository phải ưu tiên:

1. An toàn dữ liệu.
2. Bảo mật credential.
3. Tính đúng đắn của database operation.
4. Khả năng kiểm thử.
5. Hiệu năng.
6. Trải nghiệm native macOS.
7. Khả năng bảo trì.
8. Phạm vi task được giao.

Không đánh đổi an toàn dữ liệu để hoàn thành task nhanh hơn.

---

## 2. Instruction Priority

Khi làm việc trong repository, áp dụng thứ tự:

1. Yêu cầu trực tiếp của người dùng.
2. `AGENTS.md` gần file đang chỉnh sửa nhất.
3. `AGENTS.md` tại repository root.
4. Tài liệu kiến trúc trong `docs/adr/`.
5. `CONTRIBUTING.md`.
6. Coding conventions hiện có.

Khi có xung đột, phải báo rõ xung đột thay vì âm thầm chọn một phương án.

---

## 3. Planning Gate

Trước khi sửa code, agent phải:

- Đọc `AGENTS.md`.
- Đọc `README.md`.
- Đọc tài liệu liên quan trong `docs/`.
- Kiểm tra trạng thái Git.
- Xác định module bị ảnh hưởng.
- Tìm test hiện có.
- Viết kế hoạch ngắn.
- Nêu rõ file dự kiến thay đổi.
- Nêu rõ test dự kiến chạy.
- Nêu rõ rủi ro database hoặc security.

Không bắt đầu refactor lớn khi task chỉ yêu cầu sửa nhỏ.

Không mở rộng scope mà không có lý do rõ ràng.

---

## 4. Intellectual Property Rules

Sản phẩm phải độc lập.

Cấm:

- Sao chép source code từ Navicat hoặc phần mềm thương mại khác.
- Reverse engineer binary để sao chép implementation.
- Sao chép icon, logo hoặc asset.
- Sao chép pixel-by-pixel giao diện.
- Dùng tên thương hiệu của đối thủ trong tên sản phẩm.
- Sao chép nội dung hướng dẫn hoặc marketing.
- Dùng private API không được cấp phép.
- Trích xuất protocol độc quyền bằng hành vi không được phép.

Được phép:

- Xây dựng các chức năng quản trị database phổ biến.
- Tham khảo public documentation.
- Tuân theo macOS Human Interface Guidelines.
- Học từ các interaction pattern phổ biến, không độc quyền.
- Thiết kế visual identity riêng.

---

## 5. Architecture Boundaries

Kiến trúc mặc định:

```text
macOS UI
    ↓
Application Services
    ↓
Domain Interfaces
    ↓
Rust Core / Database Adapters
    ↓
Database Drivers
```

UI không được:

- Gọi database driver trực tiếp.
- Tự tạo connection string.
- Tự lưu password.
- Tự triển khai retry query.
- Chứa logic schema diff.
- Chứa SQL dialect-specific logic ngoài presentation formatting.

Database adapter không được:

- Phụ thuộc vào SwiftUI hoặc AppKit.
- Hiển thị dialog.
- Truy cập trực tiếp UI state.
- Ghi secrets vào log.

Mọi database-specific behavior phải đi qua capability interface.

---

## 6. Module Design

Ưu tiên feature modules có boundary rõ ràng.

Tên module đề xuất:

```text
AppShell
Workspace
Connections
KeychainSecurity
DatabaseCore
DatabaseAdapters
ObjectExplorer
QueryEditor
QueryExecution
ResultGrid
DataEditor
ObjectDesigner
SchemaDiff
DataDiff
DataTransfer
ImportExport
BackupRestore
Modeling
Monitoring
Automation
AIAssistant
Diagnostics
SharedUI
TestSupport
```

Không tạo “Utils” hoặc “Helpers” thành nơi chứa logic hỗn tạp.

Mỗi abstraction phải có mục đích cụ thể.

---

## 7. Swift Rules

Áp dụng khi chỉnh sửa Swift:

- Bật strict concurrency khi project hỗ trợ.
- Ưu tiên value types cho immutable models.
- UI state phải cập nhật trên `MainActor`.
- Database và file I/O không chạy trên main thread.
- Không dùng force unwrap trừ trường hợp invariant đã được chứng minh và có giải thích.
- Không dùng `try!` trong production code.
- Không bỏ qua error bằng `try?` khi error có ý nghĩa.
- Dùng typed errors.
- Không catch error rồi bỏ qua.
- Không tạo singleton toàn cục cho mutable state.
- Dependency phải được inject.
- View không chứa business logic phức tạp.
- Không đặt network hoặc database call trực tiếp trong SwiftUI `body`.
- Tách state ownership rõ ràng.
- Hỗ trợ cancellation.
- Không tạo unstructured task khi structured concurrency có thể đáp ứng.
- Không giữ secret trong `UserDefaults`.
- Không đưa secret vào `Codable` model được persist thông thường.

Tuân thủ formatter và linter đã được cấu hình trong repository.

---

## 8. Rust Rules

Áp dụng khi chỉnh sửa Rust:

- Code phải pass `cargo fmt`.
- Code phải pass `cargo clippy` với warning nghiêm trọng được xử lý.
- Không dùng `unsafe` trừ FFI boundary hoặc trường hợp đã được chứng minh.
- Mỗi block `unsafe` phải có `SAFETY:` comment.
- Không dùng `unwrap()` hoặc `expect()` trong production path khi lỗi có thể xảy ra từ input, network, database hoặc file.
- Dùng typed error.
- Không log secrets.
- Query result phải hỗ trợ streaming.
- Mọi operation chạy lâu phải hỗ trợ cancellation khi driver cho phép.
- Bounded channel thay cho unbounded channel.
- Không spawn task không được quản lý.
- Không block async runtime bằng synchronous I/O.
- Database-specific code phải nằm trong adapter tương ứng.
- Shared domain model không được phụ thuộc trực tiếp vào một database driver cụ thể.
- FFI types phải nhỏ, ổn định và được version hóa.
- Không truyền reference có lifetime phức tạp qua FFI.
- Panic không được đi qua FFI boundary.
- Chuyển panic thành controlled error tại boundary phù hợp.

---

## 9. FFI Rules

Mọi thay đổi Swift/Rust boundary phải:

- Có ownership rõ ràng.
- Có lifecycle rõ ràng.
- Không để dangling pointer.
- Không truyền secret không cần thiết.
- Không truyền nguyên result set lớn qua một lần gọi.
- Sử dụng streaming hoặc chunking.
- Có error mapping.
- Có cancellation mapping.
- Có thread-safety contract.
- Có version compatibility.
- Có integration test.

Thay đổi public FFI contract cần ADR hoặc cập nhật tài liệu kiến trúc.

---

## 10. Database Adapter Rules

Mỗi adapter phải khai báo capability.

Ví dụ:

```text
supportsTransactions
supportsSchemas
supportsQueryCancellation
supportsExplain
supportsExplainAnalyze
supportsStoredProcedures
supportsMaterializedViews
supportsNativeBackup
supportsUserManagement
supportsStreaming
supportsReturningClause
supportsTransactionalDDL
```

Không giả định capability dựa trên tên database.

Không hiển thị tính năng không được adapter hỗ trợ.

Không mô phỏng tính năng database nguy hiểm theo cách thiếu chính xác.

Mọi SQL generated theo dialect phải có test.

---

## 11. Database Safety Rules

Các nguyên tắc sau là bắt buộc:

- Connection có thể được đặt ở chế độ read-only.
- Production connection phải được nhận diện rõ.
- Destructive query phải được phân loại.
- `DROP`, `TRUNCATE`, unconditional `DELETE`, unconditional `UPDATE` và operation tương đương phải có safeguard.
- Không tự động retry câu lệnh ghi nếu chưa chứng minh idempotency.
- Không tự động commit transaction ngoài hành vi người dùng đã chọn.
- Khi đóng tab có transaction đang mở, phải cảnh báo.
- Khi đóng connection có pending edit, phải cảnh báo.
- Data grid update phải xác định record bằng key an toàn.
- Bảng không có unique identifier phải được xử lý read-only hoặc có cảnh báo đặc biệt.
- Schema sync phải có preview.
- Data sync phải có dry run hoặc summary trước khi apply.
- Migration nguy hiểm phải có typed confirmation.
- Generated SQL phải hiển thị được cho người dùng.
- Query cancellation phải được truyền xuống driver khi được hỗ trợ.

Thay đổi liên quan database write phải có test success, failure và rollback behavior.

---

## 12. Credential Rules

Cấm lưu plaintext credential trong:

- Source code.
- Git history.
- `UserDefaults`.
- Local SQLite metadata.
- JSON export.
- Log.
- Crash report.
- Analytics.
- Test snapshot.
- Screenshot fixture.
- Clipboard lâu dài.

Credential production phải được lưu bằng macOS Keychain.

Connection export mặc định không chứa:

- Password.
- Private key passphrase.
- API key.
- Access token.
- Refresh token.
- Client secret.

Test phải sử dụng credential giả hoặc environment secret được CI quản lý.

Không in environment variables trong test log.

---

## 13. TLS and SSH Rules

TLS:

- Certificate validation bật mặc định.
- Hostname validation bật mặc định.
- Không có global insecure mode.
- Custom CA phải được user chọn rõ ràng.
- Mọi bypass tạm thời phải có cảnh báo và scope theo connection.
- Không log certificate private key.

SSH:

- Xác minh host key.
- Có known-host policy.
- Host key thay đổi phải cảnh báo.
- Private key phải có permission phù hợp.
- Không gọi shell bằng string interpolation.
- Jump host phải có security model riêng.
- Tunnel phải đóng sạch khi connection kết thúc.
- Tunnel lỗi không được âm thầm fallback sang direct connection.

---

## 14. Logging Rules

Sử dụng structured logging.

Mọi log có thể chứa dữ liệu nhạy cảm phải đi qua redaction.

Không log:

- Password.
- Token.
- Full connection string.
- Private key.
- Query parameter nhạy cảm.
- Toàn bộ row data.
- Nội dung clipboard.

Error log cần chứa:

- Operation ID.
- Adapter.
- Error category.
- Retryability.
- User-safe message.
- Internal diagnostic context đã được redaction.

---

## 15. Query Execution Rules

Mọi query execution phải xác định:

- Connection.
- Database/schema context.
- Transaction mode.
- Timeout.
- Row limit.
- Cancellation handle.
- Execution ID.
- Result streaming policy.
- Error handling.
- Logging policy.

Không chạy query trên main thread.

Không đọc toàn bộ result set vào memory.

Khi result vượt giới hạn:

- Dừng fetch.
- Hoặc chuyển sang streaming/export.
- Hoặc yêu cầu user tải thêm.

Không tự động chạy lại query ghi sau connection error.

---

## 16. Data Grid Rules

Data grid phải:

- Virtualized.
- Có bounded memory.
- Hỗ trợ server-side pagination hoặc streaming.
- Phân biệt value chưa tải, `NULL` và empty string.
- Giữ type information.
- Không chuyển tất cả giá trị thành string trong core.
- Hiển thị pending edits.
- Cho phép rollback pending edits.
- Xác định row bằng primary key hoặc unique key.
- Có optimistic concurrency strategy.
- Không apply edit ngoài ý muốn khi scroll.
- Không mất edit khi refresh mà không cảnh báo.
- Không tải blob lớn mặc định.

Mọi bug có khả năng sửa nhầm row được xếp mức nghiêm trọng cao nhất.

## Data Type Styling Rules

Data grid phải hỗ trợ style theo normalized data type.

Yêu cầu:

- Mapping màu không được phụ thuộc trực tiếp vào raw database type name.
- Database adapter phải map type riêng về nhóm type chuẩn.
- Style resolution không được nằm trong database adapter.
- Theme engine phải tách biệt khỏi query execution và data model.
- Màu phải hoạt động đúng trong Light Mode và Dark Mode.
- Không chỉ dùng màu để biểu thị `NULL`, primary key, foreign key hoặc modified cell.
- Phải có accessibility fallback bằng icon, text style hoặc tooltip.
- User-defined color phải được kiểm tra contrast hoặc cảnh báo khi contrast quá thấp.
- Không lưu theme preference trong database connection secret.
- Thay đổi màu không được làm mất selection, scroll position hoặc pending edits.
- Không render lại toàn bộ dataset khi chỉ đổi theme.
- Phải có snapshot test hoặc UI test cho các nhóm data type chính.

---

## 17. Import and Export Rules

Import:

- Không tin tưởng file input.
- Có giới hạn kích thước và memory.
- Chống path traversal.
- Xử lý encoding rõ ràng.
- Preview trước import.
- Không đoán type một cách không thể review.
- Có error-row report.
- Có transaction policy.
- Hỗ trợ cancel.

Export:

- Escape CSV đúng chuẩn.
- Chống spreadsheet formula injection.
- Không overwrite file khi chưa xác nhận.
- Dùng atomic write khi phù hợp.
- Không ghi secret.
- Export lớn phải streaming.
- Temporary file phải có permission an toàn.
- File chưa hoàn tất phải được đánh dấu hoặc xóa sạch sau lỗi.

---

## 18. SQL Generation Rules

Generated SQL phải:

- Theo đúng dialect.
- Quote identifier đúng.
- Escape literal đúng.
- Sử dụng parameter binding khi operation cho phép.
- Có deterministic output.
- Có test snapshot hoặc semantic test.
- Không nối trực tiếp user input vào SQL.
- Hiển thị preview cho operation nguy hiểm.
- Có dependency ordering cho migration.
- Không giả định DDL transactional.

Không dùng regex đơn giản làm parser duy nhất cho các safety-critical operation.

---
---

## 19. UI and UX Rules

Mọi UI phải:

- Hỗ trợ Dark Mode và Light Mode.
- Hoạt động bằng keyboard.
- Có accessibility label cho control quan trọng.
- Không block main thread.
- Có loading state.
- Có empty state.
- Có error state.
- Có cancellation khi operation dài.
- Hiển thị connection context.
- Hiển thị rõ production context.
- Giữ unsaved query.
- Cảnh báo transaction chưa kết thúc.
- Dùng system component khi phù hợp.
- Không hardcode kích thước khiến UI vỡ khi resize.
- Không sao chép trực tiếp UI của sản phẩm đối thủ.

Text hiển thị cho người dùng phải mô tả hậu quả, không chỉ hiển thị error code.

---

## 20. Accessibility Rules

Tính năng mới phải xem xét:

- VoiceOver.
- Keyboard navigation.
- Focus order.
- Contrast.
- Dynamic text behavior phù hợp trên macOS.
- Không chỉ sử dụng màu để biểu thị trạng thái.
- Accessible labels cho icon-only buttons.
- Reduce Motion khi có animation.

Production warning không được chỉ thể hiện bằng màu đỏ.

---

## 21. Performance Rules

Không merge thay đổi:

- Load toàn bộ table vào RAM.
- Load toàn bộ object tree ngay khi connect.
- Block main thread bằng database hoặc file I/O.
- Tạo unbounded cache.
- Tạo unbounded task queue.
- Render hàng chục nghìn row cùng lúc.
- Đọc blob lớn mặc định.
- Chạy schema introspection lặp lại không cache.

Mọi cache phải có:

- Ownership.
- Size limit.
- Invalidation policy.
- Lifetime.
- Thread-safety policy.

Performance-sensitive change phải có benchmark hoặc measurement.

---

## 22. Dependency Rules

Trước khi thêm dependency:

- Kiểm tra license.
- Kiểm tra maintenance status.
- Kiểm tra security advisories.
- Kiểm tra Apple Silicon.
- Kiểm tra binary size.
- Kiểm tra transitive dependencies.
- Kiểm tra khả năng thay thế.
- Giải thích vì sao standard library hoặc dependency hiện tại không đủ.

Không thêm dependency chỉ để tránh viết một lượng code nhỏ và rõ ràng.

Không dùng package không rõ nguồn gốc.

Không đổi major version nhiều dependency trong cùng một task trừ task nâng cấp riêng.

---

## 23. Testing Rules

Thay đổi production code phải có test tương ứng.

Tối thiểu:

- Happy path.
- Failure path.
- Cancellation khi phù hợp.
- Edge case.
- Security regression khi liên quan.
- Database dialect regression khi liên quan.

Bug fix phải có regression test chứng minh bug cũ.

Không xóa test chỉ để CI pass.

Không làm yếu assertion.

Không tăng timeout tùy tiện để che flaky test.

Không đánh dấu test skip mà không ghi lý do và issue theo dõi.

---

## 24. Test Database Rules

Không chạy automated test trên database production hoặc staging dùng chung.

Integration test phải sử dụng:

- Disposable container.
- Ephemeral database.
- Isolated schema.
- Deterministic fixture.

Test phải tự cleanup.

Tên database test phải thể hiện rõ là test.

Destructive integration test phải có guard chống chạy nhầm host.

---

## 25. Build and Validation

Trước khi báo hoàn thành, chạy các lệnh tương ứng với phần đã sửa.

Ví dụ, tùy cấu hình repository:

```bash
swiftformat --lint .
swiftlint
xcodebuild build
xcodebuild test

cargo fmt --check
cargo clippy --all-targets --all-features -- -D warnings
cargo test --all-features
```

Ngoài ra phải chạy:

- Unit tests liên quan.
- Integration tests liên quan.
- UI tests khi thay đổi user flow.
- Security tests khi thay đổi credential, TLS, SSH, import/export hoặc query safety.
- Performance tests khi thay đổi streaming, grid hoặc diff engine.

Không tuyên bố test pass nếu chưa chạy.

Nếu không thể chạy test, phải ghi chính xác:

- Test nào chưa chạy.
- Lý do.
- Rủi ro còn lại.
- Cách người review có thể chạy.

---

## 26. Git Rules

Trước khi sửa:

- Kiểm tra `git status`.
- Không ghi đè thay đổi chưa commit của người khác.
- Không revert file ngoài scope.
- Không dùng destructive Git command khi chưa được yêu cầu.

Commit phải:

- Nhỏ.
- Có mục đích rõ.
- Không chứa secret.
- Không chứa build artifact.
- Không chứa dữ liệu database thật.
- Không chứa file IDE cá nhân không cần thiết.

Không force push trừ khi được yêu cầu rõ ràng.

---

## 27. Documentation Rules

Cập nhật tài liệu khi thay đổi:

- Public architecture.
- Database capability.
- FFI contract.
- Security model.
- User-visible behavior.
- Build command.
- Test command.
- Distribution process.
- New dependency.
- New entitlement.

Architecture decision quan trọng phải có ADR.

ADR không được sửa lịch sử quyết định cũ theo cách làm mất context. Khi quyết định thay đổi, tạo ADR mới để supersede.

---

## 28. Error Handling Rules

Error phải được phân loại tối thiểu:

- Configuration.
- Authentication.
- Authorization.
- Network.
- TLS.
- SSH.
- Timeout.
- Cancellation.
- Database.
- Query syntax.
- Constraint.
- Transaction.
- File.
- Import.
- Export.
- Internal.
- Unsupported capability.

Error user-facing phải:

- Dễ hiểu.
- Có context phù hợp.
- Không chứa secret.
- Đưa ra hành động tiếp theo khi có thể.

Không hiển thị raw stack trace cho người dùng cuối.

---

## 29. Definition of Done

Một task chỉ được coi là hoàn thành khi:

- Phạm vi yêu cầu đã được đáp ứng.
- Không có thay đổi ngoài scope không được giải thích.
- Code build được.
- Test liên quan pass.
- Linter pass.
- Formatter pass.
- Không có secret.
- Không có warning nghiêm trọng mới.
- Error handling đầy đủ.
- Cancellation được xử lý khi cần.
- Security impact đã được xem xét.
- Database safety đã được xem xét.
- Documentation được cập nhật.
- Agent trình bày danh sách file đã thay đổi.
- Agent trình bày lệnh đã chạy.
- Agent trình bày kết quả test.
- Agent nêu rõ rủi ro hoặc phần chưa xác minh.

---

## 30. Completion Report Format

Khi hoàn thành task, trả lời theo mẫu:

```text
Summary
- Những gì đã thực hiện.

Files changed
- File và lý do thay đổi.

Architecture
- Quyết định kiến trúc hoặc boundary bị ảnh hưởng.

Database safety
- Safeguard đã áp dụng.

Security
- Tác động bảo mật và cách xử lý.

Tests
- Lệnh đã chạy.
- Kết quả.

Not tested
- Những phần chưa thể kiểm tra và lý do.

Risks
- Rủi ro còn lại.

Next recommended task
- Chỉ một bước tiếp theo hợp lý.
```

Không dùng các câu chung chung như “mọi thứ hoạt động tốt” nếu không có bằng chứng từ build hoặc test.
