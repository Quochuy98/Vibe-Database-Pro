# MASTER PROMPT — CODEX PLAN FOR A PROFESSIONAL macOS DATABASE CLIENT

## NHIỆM VỤ

Bạn là Principal Software Architect, macOS Engineer, Database Tooling Engineer, Product Manager và Security Engineer.

Hãy lập kế hoạch chi tiết để xây dựng một ứng dụng quản trị cơ sở dữ liệu chuyên nghiệp dành cho macOS, có phạm vi chức năng tương đương nhóm công cụ như Navicat Premium, nhưng phải là một sản phẩm hoàn toàn độc lập.

Tên mã tạm thời:

**DataForge for macOS**

Không sử dụng tên Navicat trong source code, bundle identifier, giao diện, tài nguyên, tài liệu marketing hoặc tên sản phẩm cuối cùng.

---

## 1. CHẾ ĐỘ THỰC HIỆN

Trong nhiệm vụ này, bạn chỉ được:

- Phân tích yêu cầu.
- Khảo sát repository hiện tại.
- Đề xuất kiến trúc.
- Xây dựng product specification.
- Lập feature matrix.
- Chia milestone.
- Tạo backlog kỹ thuật.
- Xác định rủi ro.
- Đề xuất prototype hoặc technical spike.
- Tạo tài liệu kế hoạch trong thư mục `docs/`.

Không được bắt đầu triển khai chức năng production.

Không được viết hàng loạt source code.

Chỉ được tạo code khi cần một technical spike rất nhỏ để kiểm chứng tính khả thi, và phải giải thích rõ:

- Giả thuyết cần kiểm chứng.
- Phạm vi spike.
- Tiêu chí thành công.
- Cách xóa hoặc thay thế spike sau khi hoàn thành.

Trước khi thay đổi bất kỳ source code nào, phải trình bày kế hoạch và chờ yêu cầu triển khai riêng.

---

## 2. MỤC TIÊU SẢN PHẨM

Xây dựng một database management application dành riêng cho macOS, có trải nghiệm native, nhanh, ổn định và an toàn.

Ứng dụng cần giúp developer, DBA và data engineer:

- Quản lý nhiều kết nối cơ sở dữ liệu.
- Duyệt database, schema và object.
- Viết, chạy và phân tích câu lệnh SQL.
- Xem và chỉnh sửa dữ liệu.
- Thiết kế database object.
- So sánh và đồng bộ cấu trúc.
- So sánh và đồng bộ dữ liệu.
- Import, export và chuyển dữ liệu.
- Backup và restore.
- Thiết kế ER diagram và data model.
- Theo dõi server và session.
- Tạo tác vụ tự động.
- Quản lý snippets, lịch sử và workspace.

Sản phẩm phải có thiết kế, tên gọi, icon, interaction pattern và visual identity riêng.

Không sao chép pixel-by-pixel giao diện của bất kỳ sản phẩm thương mại nào.

---

## 3. NỀN TẢNG MỤC TIÊU

Ưu tiên:

- macOS.
- Apple Silicon.
- Native macOS experience.
- Dark Mode và Light Mode.
- Keyboard-first workflow.
- Multi-window.
- Tabbed workspace.
- Menu bar chuẩn macOS.
- Command Palette.
- Drag and drop.
- Accessibility.
- High-DPI display.
- Code signing và notarization.

Trong kế hoạch, hãy đánh giá:

- Phiên bản macOS deployment target phù hợp.
- Apple Silicon only hay Universal Binary.
- Phân phối trực tiếp bằng Developer ID hay Mac App Store.
- Ảnh hưởng của App Sandbox đến SSH, truy cập file, database driver, subprocess, backup tool và automation.
- Cơ chế auto-update.
- Cơ chế crash reporting opt-in.
- Khả năng phát hành bản Community và bản Pro trong tương lai.

---

## 4. KIẾN TRÚC MẶC ĐỊNH

### 4.1 Presentation Layer

- Swift.
- SwiftUI cho application shell và các màn hình thông thường.
- AppKit cho những thành phần cần khả năng desktop nâng cao.
- `NSDocument` hoặc kiến trúc workspace tương đương cho tài liệu và cửa sổ.
- `NSTextView`/TextKit 2 hoặc editor engine phù hợp cho SQL editor.
- `NSOutlineView` hoặc giải pháp tương đương cho database object tree.
- Data grid có virtualization, không render toàn bộ dataset cùng lúc.

### 4.2 Core Layer

Ưu tiên sử dụng Rust cho:

- Database connection abstraction.
- Connection pooling.
- Query execution.
- Query cancellation.
- Streaming result.
- Metadata introspection.
- Schema normalization.
- SQL dialect abstraction.
- Import/export pipeline.
- Data diff.
- Schema diff.
- Migration plan generation.
- Secure serialization.
- Background job engine.

Kết nối Swift và Rust bằng một trong các phương án:

- UniFFI.
- C ABI.
- Swift-compatible generated bindings.

Hãy so sánh các phương án và chọn một phương án chính thức bằng Architecture Decision Record.

### 4.3 Local Persistence

Dữ liệu cục bộ có thể bao gồm:

- Workspace.
- Query history.
- Saved query.
- Snippet.
- UI state.
- Job history.
- Non-sensitive connection metadata.
- User preferences.

Có thể sử dụng SQLite cho local metadata.

Không lưu plaintext:

- Password.
- Private key passphrase.
- API key.
- Access token.
- Refresh token.
- Database credential.

Mọi secret phải được lưu trong macOS Keychain hoặc cơ chế bảo mật tương đương.

### 4.4 Architecture Style

Đánh giá và lựa chọn rõ ràng giữa:

- Modular Clean Architecture.
- Hexagonal Architecture.
- Feature-based modular architecture.

Phải tách biệt:

- UI.
- Application services.
- Domain model.
- Database adapters.
- Infrastructure.
- Security.
- Persistence.
- Background jobs.
- Plugin interfaces.

Database-specific logic không được rò rỉ trực tiếp vào UI layer.

---

## 5. DATABASE SUPPORT ROADMAP

Không cố triển khai tất cả database engine trong một milestone.

### Phase 1 — MVP

Ưu tiên:

- PostgreSQL.
- MySQL.
- MariaDB.
- SQLite.

### Phase 2

Bổ sung:

- Microsoft SQL Server.
- Redis.
- MongoDB.

### Phase 3

Đánh giá:

- Oracle.
- Snowflake.
- Amazon Redshift.
- ClickHouse.
- CockroachDB.
- TiDB.
- OceanBase.
- Các dịch vụ database cloud phổ biến.

Mỗi database adapter phải khai báo capability riêng, ví dụ:

- Transactions.
- Schema support.
- Stored procedures.
- Functions.
- Triggers.
- Views.
- Materialized views.
- Explain plan.
- Backup.
- Restore.
- User management.
- Streaming.
- Cancel query.
- Native tunnel.
- Binary field.
- JSON field.
- Array field.
- Spatial field.

Không giả định mọi database đều hỗ trợ cùng một tính năng.

---

## 6. DANH SÁCH TÍNH NĂNG

Hãy phân loại mỗi tính năng thành:

- MVP.
- Post-MVP.
- Advanced.
- Enterprise.
- Deferred.
- Not recommended.

Mỗi tính năng cần có:

- User story.
- Functional requirements.
- Non-functional requirements.
- Dependencies.
- Security concerns.
- Technical risks.
- Acceptance criteria.
- Test strategy.
- Estimated complexity: S, M, L hoặc XL.

### 6.1 Connection Manager

Bao gồm:

- Tạo, sửa, xóa và nhân bản connection.
- Connection groups.
- Màu nhận diện connection.
- Test connection.
- Connection timeout.
- Read timeout.
- Keep-alive.
- Connection pooling.
- Auto reconnect có kiểm soát.
- Read-only connection mode.
- Development, staging và production labels.
- Cảnh báo nổi bật khi kết nối production.
- Import/export connection metadata.
- Không export secret theo mặc định.
- SSL/TLS.
- CA certificate.
- Client certificate.
- SSH tunnel.
- SSH password.
- SSH private key.
- SSH agent.
- Proxy jump/bastion host.
- Cloud database connection presets.
- Multiple authentication modes tùy database.
- Keychain integration.

### 6.2 Database Object Explorer

Bao gồm:

- Server.
- Database.
- Schema.
- Table.
- Column.
- Index.
- Primary key.
- Foreign key.
- Constraint.
- View.
- Materialized view.
- Function.
- Procedure.
- Trigger.
- Sequence.
- Event.
- User.
- Role.
- Extension.
- Database-specific object.

Yêu cầu:

- Lazy loading.
- Refresh từng node.
- Search object.
- Filter object.
- Favorite object.
- Virtual group.
- Copy qualified name.
- Open object bằng keyboard.
- Object details.
- Generated DDL.
- Dependency view.

### 6.3 SQL Editor

Bao gồm:

- Multi-tab editor.
- Syntax highlighting.
- Line number.
- Code folding.
- Multiple cursors.
- Find and replace.
- SQL formatting.
- Minify.
- Comment/uncomment.
- Auto indentation.
- Bracket matching.
- Snippets.
- Query history.
- Saved query.
- Recent files.
- Parameterized query.
- Run current statement.
- Run selected statements.
- Run entire script.
- Transaction mode.
- Auto-commit toggle.
- Commit.
- Rollback.
- Stop/cancel query.
- Query timeout.
- Execution duration.
- Affected rows.
- Multiple result sets.
- Messages and warnings panel.
- Explain.
- Explain Analyze.
- Visual execution plan.
- SQL dialect awareness.
- Code completion dựa trên schema metadata.
- Table and column suggestions.
- Function suggestions.
- Alias-aware suggestions.
- Error position highlighting.
- Safe query mode.

Phải thiết kế riêng cách xử lý:

- Script rất lớn.
- Query chạy lâu.
- Query trả hàng triệu dòng.
- Connection bị mất.
- Transaction đang mở khi đóng tab.
- Query có nhiều statements.
- Query chạy trên production.

### 6.4 Data Viewer and Data Editor

Bao gồm:

- Virtualized grid.
- Server-side pagination.
- Configurable page size.
- Filter builder.
- Sort.
- Column visibility.
- Column reorder.
- Freeze column.
- Resize column.
- Copy cell.
- Copy row.
- Copy as SQL.
- Copy as CSV/JSON.
- Inline editing.
- Insert row.
- Duplicate row.
- Delete row.
- Batch edit.
- Pending changes indicator.
- Preview generated SQL.
- Apply changes.
- Rollback changes.
- Null editor.
- Boolean editor.
- Date/time editor.
- JSON editor.
- Text editor.
- Hex viewer.
- Binary/image preview.
- Foreign key lookup.
- Read-only detection.
- Primary-key awareness.
- Optimistic concurrency check.
- Export current result.

Không được tải toàn bộ bảng vào RAM.

Phải có giới hạn bảo vệ khi bảng không có primary key hoặc unique key.
### Data Type Color Customization

Bao gồm:

- Cho phép người dùng cấu hình màu chữ và màu nền theo từng loại dữ liệu.
- Hỗ trợ cấu hình riêng cho:
  - Integer.
  - Decimal/Float.
  - String/Text.
  - Boolean.
  - Date.
  - Time.
  - DateTime/Timestamp.
  - UUID.
  - JSON/JSONB.
  - XML.
  - Binary/BLOB.
  - Enum.
  - Array.
  - Spatial/Geometry.
  - NULL.
  - Primary key.
  - Foreign key.
  - Generated/Computed column.
  - Database-specific data types.
- Có màu mặc định phù hợp cho Light Mode và Dark Mode.
- Cho phép bật hoặc tắt hoàn toàn chức năng tô màu theo kiểu dữ liệu.
- Cho phép chọn:
  - Text color.
  - Cell background color.
  - Font weight.
  - Font style.
- Cho phép cấu hình màu riêng theo:
  - Toàn ứng dụng.
  - Từng connection.
  - Từng database.
  - Từng table hoặc result grid.
- Có nút reset về theme mặc định.
- Có preview trực tiếp trong Settings.
- Có preset màu:
  - Default.
  - High Contrast.
  - Color Blind Friendly.
  - Minimal.
- Không chỉ sử dụng màu để truyền đạt ý nghĩa.
- Có tooltip hoặc icon hỗ trợ nhận diện kiểu dữ liệu.
- Màu phải đảm bảo contrast và accessibility.
- Không làm giảm hiệu năng khi render hoặc scroll dữ liệu lớn.
- Không tạo lại toàn bộ grid khi chỉ thay đổi theme.
- Quy tắc màu phải dựa trên normalized data type, không chỉ dựa vào tên type dạng string.
### 6.5 Object Designer

Thiết kế giao diện tạo và sửa:

- Table.
- Column.
- Index.
- Primary key.
- Foreign key.
- Unique constraint.
- Check constraint.
- View.
- Function.
- Procedure.
- Trigger.
- Sequence.

Yêu cầu:

- Form-based designer.
- SQL preview.
- Database-specific options.
- Validation.
- Unsaved changes protection.
- Generated migration preview.
- Không tự động apply thay đổi nguy hiểm.

### 6.6 Schema Diff and Synchronization

Bao gồm:

- Chọn source và target.
- Introspect schema.
- Normalize metadata.
- Detect added, removed và changed objects.
- Dependency ordering.
- Rename detection có cảnh báo.
- Migration SQL generation.
- Preview.
- Include/exclude object.
- Dry run.
- Backup recommendation.
- Destructive operation warning.
- Transaction wrapping khi database hỗ trợ.
- Save comparison profile.
- Comparison history.

Không apply schema synchronization ngay sau khi comparison.

Phải có bước review rõ ràng.

### 6.7 Data Diff and Synchronization

Bao gồm:

- Source/target selection.
- Table mapping.
- Column mapping.
- Key selection.
- Filter.
- Batch size.
- Insert/update/delete detection.
- One-way sync.
- Bidirectional sync chỉ khi có chiến lược conflict rõ ràng.
- Dry run.
- Preview sample.
- Generated operation summary.
- Resume/retry.
- Progress reporting.
- Cancel operation.
- Verification.
- Audit log cục bộ.

### 6.8 Data Transfer

Bao gồm:

- Same-engine transfer.
- Cross-engine transfer.
- Data type mapping.
- Table mapping.
- Column mapping.
- Batch transfer.
- Streaming.
- Retry.
- Resume.
- Error row export.
- Transaction boundaries.
- Progress.
- Cancel.
- Transfer report.
- Schema creation option.
- Data-only option.
- Structure-only option.

### 6.9 Import and Export

Hỗ trợ theo từng giai đoạn:

- CSV.
- TSV.
- JSON.
- SQL.
- XML.
- XLSX.
- Parquet trong giai đoạn nâng cao.

Import cần có:

- Encoding detection.
- Delimiter.
- Header mapping.
- Type inference.
- Preview.
- Null mapping.
- Date/time format.
- Error policy.
- Batch size.
- Transaction mode.

Export cần có:

- Current page.
- Entire result.
- Selected rows.
- Selected columns.
- Streaming export.
- Compression.
- Encoding.
- Date format.
- Null representation.

### 6.10 Backup and Restore

Thiết kế adapter riêng theo database.

Đánh giá:

- Native database utilities.
- Library-level backup.
- Logical dump.
- Physical backup.
- Process execution.
- Sandbox limitations.
- Progress reporting.
- Restore validation.
- Credential handling.
- Cancel behavior.
- Backup retention.
- Encryption.
- Compression.

Không tự xây lại engine backup phức tạp khi database đã có công cụ chính thức đáng tin cậy.

### 6.11 ER Diagram and Data Modeling

Bao gồm:

- Reverse engineer database.
- Table nodes.
- Relationship edges.
- Auto layout.
- Manual layout.
- Zoom and pan.
- Minimap.
- Notes.
- Groups/layers.
- Search.
- Export PNG/PDF/SVG.
- Generate SQL.
- Compare model with database.
- Apply model changes sau bước review.
- Conceptual model trong giai đoạn nâng cao.
- Logical model trong giai đoạn nâng cao.
- Physical model.
- Model versioning.

### 6.12 Monitoring

Tùy database capability:

- Active sessions.
- Running queries.
- Locks.
- Blocking queries.
- Transactions.
- Server variables.
- Database size.
- Table size.
- Connections.
- Query duration.
- Kill session.
- Cancel query.

Kill session và cancel query phải có permission check và confirmation.

### 6.13 User and Role Management

Bao gồm:

- List users and roles.
- Create user.
- Edit user.
- Disable/drop user.
- Role membership.
- Database privileges.
- Schema privileges.
- Table privileges.
- Generated SQL preview.
- Database-specific capability checks.

Mọi thay đổi privilege phải hiển thị SQL hoặc operation preview trước khi thực thi.

### 6.14 Automation

Bao gồm:

- Saved jobs.
- Query jobs.
- Import/export jobs.
- Backup jobs.
- Data transfer jobs.
- Schema comparison jobs.
- Data comparison jobs.
- Schedule.
- Manual run.
- Retry.
- Job log.
- Notification.
- Failure report.
- Credential access policy.
- Background helper evaluation.
- macOS launch agent evaluation.

Phải phân tích rõ ứng dụng có thể chạy job khi:

- App đang mở.
- App chạy nền.
- User đã logout.
- Mac đang sleep.
- Credential nằm trong Keychain.
- Database yêu cầu SSH tunnel.


## 7. DATABASE SAFETY

Đây là yêu cầu bắt buộc.

Phải thiết kế:

- Read-only mode cho connection.
- Production environment badge.
- Production connection color.
- Confirmation cho destructive SQL.
- SQL parser hoặc statement classifier.
- Cảnh báo với `DROP`, `TRUNCATE`, `DELETE` không có điều kiện, `UPDATE` không có điều kiện và các operation nguy hiểm tương đương.
- Preview số lượng bản ghi có khả năng bị ảnh hưởng khi khả thi.
- Require typed confirmation cho operation có mức rủi ro cao.
- Không retry tự động câu lệnh ghi nếu không chứng minh được idempotency.
- Transaction state indicator.
- Unsaved transaction warning.
- Query cancellation.
- Statement timeout.
- Result row limit.
- Export size warning.
- Audit log cục bộ cho thao tác nguy hiểm.
- Không ghi log plaintext password hoặc token.
- Không đưa secrets vào crash report.

Mọi safety mechanism phải có test.

---

## 8. SECURITY REQUIREMENTS

Phải lập threat model cho ít nhất các nhóm:

- Credential theft.
- Malicious database server.
- Man-in-the-middle.
- SSH host impersonation.
- Certificate validation bypass.
- SQL injection trong internal query generation.
- Malicious CSV/JSON/XML/XLSX.
- Formula injection khi export spreadsheet.
- Path traversal.
- Unsafe temporary files.
- Command injection khi gọi native database tools.
- Secrets trong logs.
- Secrets trong crash reports.
- Secrets trong clipboard.
- Untrusted plugin.
- Compromised auto-update.
- Supply-chain attack.

Bắt buộc:

- Secrets trong Keychain.
- TLS certificate validation mặc định.
- Không có nút “ignore all TLS errors” toàn cục.
- SSH host key verification.
- Known-host handling.
- Secure temporary directory.
- File permission tối thiểu.
- Redacted structured logging.
- Dependency scanning.
- SBOM.
- Code signing.
- Hardened Runtime.
- Notarization.
- Secure update verification.
- Least privilege.
- Không sử dụng shell interpolation với dữ liệu người dùng.
- Không hardcode credential.
- Không commit file `.env` chứa secret.
- Không thu thập telemetry khi chưa có opt-in.

---

## 9. PERFORMANCE REQUIREMENTS

Đề xuất benchmark và performance budget cho:

- App launch.
- Connection establishment.
- Object tree load.
- Metadata refresh.
- SQL editor responsiveness.
- Completion latency.
- Rendering grid.
- Scrolling grid.
- Memory usage.
- Streaming large query results.
- Export.
- Import.
- Schema diff.
- Data transfer.
- ER diagram với nhiều bảng.

Thiết kế phải đảm bảo:

- Không giữ toàn bộ result set trong RAM.
- Backpressure.
- Streaming.
- Bounded queues.
- Cancellation propagation.
- Connection pool limits.
- Background work không block main thread.
- Large object tree sử dụng lazy loading.
- Large text/blob chỉ tải theo yêu cầu.
- Data grid sử dụng virtualization.

Hãy đưa ra benchmark dataset cụ thể.

---

## 10. UX VÀ macOS DESIGN

Ứng dụng phải mang cảm giác native macOS nhưng có visual identity riêng.

Đề xuất layout:

- Sidebar trái: connections và database objects.
- Khu vực trung tâm: tabs và editor.
- Inspector phải: context-sensitive properties.
- Bottom panel: results, messages, execution plan và logs.
- Toolbar: connection, execute, stop, commit, rollback và filter.
- Status bar: connection, database, transaction, row count và duration.

Bắt buộc hỗ trợ:

- Light Mode.
- Dark Mode.
- System accent.
- Full keyboard navigation.
- VoiceOver cơ bản.
- Resizable panes.
- Multi-window.
- Tab restoration.
- Command Palette.
- Standard macOS shortcuts.
- Context menu.
- Drag and drop khi phù hợp.
- Undo/redo cho thao tác UI và model.
- Autosave cho draft query.
- Crash recovery cho unsaved query.

Không sao chép trực tiếp:

- Icon.
- Logo.
- Artwork.
- Screenshot.
- Toolbar layout độc quyền.
- Tên tính năng mang tính thương hiệu.
- Copywriting.
- Theme.
- Asset.
- Source code.
- Binary.
- Reverse-engineered private protocol.

### Data Grid Appearance Settings

Ứng dụng phải có trang Settings để tùy chỉnh giao diện data grid:

- Font family.
- Font size.
- Row height.
- Alternating row background.
- Grid line visibility.
- Selected row appearance.
- Modified cell appearance.
- Invalid value appearance.
- NULL value appearance.
- Data type syntax colors.
- Primary key và foreign key indicators.
- Light Mode và Dark Mode palettes độc lập.
- Import/export appearance profile.
---

## 11. TEST STRATEGY

### Unit tests

- SQL statement classification.
- Schema normalization.
- Type mapping.
- Migration ordering.
- Diff algorithms.
- Connection configuration validation.
- Secret redaction.
- Import parser.
- Export escaping.
- Capability matrix.

### Integration tests

Sử dụng container hoặc test environment cho:

- PostgreSQL.
- MySQL.
- MariaDB.
- SQL Server khi bắt đầu Phase 2.
- MongoDB khi bắt đầu Phase 2.
- Redis khi bắt đầu Phase 2.

Test:

- Connect.
- Disconnect.
- Reconnect.
- TLS.
- SSH.
- Query.
- Transaction.
- Cancel.
- Metadata.
- CRUD.
- Import.
- Export.
- Schema diff.
- Data transfer.

### UI tests

- Connection flow.
- Query execution.
- Result grid.
- Data editing.
- Dangerous query confirmation.
- Transaction warning.
- Restore workspace.
- Keyboard navigation.
- Dark Mode.
- Accessibility identifiers.

### Security tests

- Secret leakage.
- Log redaction.
- Malicious filenames.
- Command injection.
- Export formula injection.
- Certificate validation.
- SSH host verification.
- Unsafe SQL detection.

### Performance tests

- Million-row streaming fixture.
- Large schema fixture.
- Large SQL file.
- Wide table.
- Large JSON document.
- High-latency connection.
- Connection interruption.
- Slow query cancellation.

Không được dùng production database cho automated tests.

---

## 12. OBSERVABILITY

Thiết kế structured logging với các mức:

- Trace.
- Debug.
- Info.
- Warning.
- Error.

Bắt buộc:

- Redact secrets.
- Redact connection strings.
- Không log query parameters nhạy cảm mặc định.
- Có correlation ID cho job.
- Có query execution ID.
- Có exportable diagnostics bundle.
- Diagnostics bundle phải cho người dùng xem trước.
- Crash reporting phải opt-in.
- Telemetry phải opt-in.
- Có nút xóa toàn bộ local history và diagnostics.

---

## 13. DISTRIBUTION

Tạo decision matrix cho:

### Phương án A — Direct Distribution

- Developer ID.
- Hardened Runtime.
- Notarization.
- Signed update.
- Auto-update framework.
- Background helper.
- Database native tools.

### Phương án B — Mac App Store

- App Sandbox.
- Entitlements.
- File access.
- Network access.
- Subprocess limitations.
- Background execution limitations.
- Review policy.
- Update flow.

Đưa ra lựa chọn khuyến nghị và giải thích.

Không mặc định rằng một binary có thể dễ dàng đáp ứng cả hai mô hình phân phối.

---

## 14. PLUGIN SYSTEM

Không triển khai plugin system trong MVP nhưng phải đánh giá khả năng mở rộng.

Plugin không được chạy tùy ý trong process chính.

Xem xét:

- Out-of-process plugin.
- Capability permissions.
- Signed plugins.
- Versioned plugin API.
- Sandbox.
- Crash isolation.
- Network permission.
- File permission.
- Secret access permission.

Database adapter nội bộ nên có interface đủ ổn định để có thể mở rộng thành plugin API trong tương lai.

---

## 15. TÀI LIỆU PHẢI TẠO

Sau khi khảo sát repository, hãy tạo hoặc đề xuất nội dung cho:

```text
docs/
├── PRODUCT_SPEC.md
├── FEATURE_MATRIX.md
├── USER_FLOWS.md
├── ARCHITECTURE.md
├── DATABASE_ADAPTERS.md
├── SECURITY_THREAT_MODEL.md
├── DATABASE_SAFETY.md
├── TEST_STRATEGY.md
├── PERFORMANCE_BUDGET.md
├── DISTRIBUTION_STRATEGY.md
├── ROADMAP.md
├── BACKLOG.md
├── RISKS.md
└── adr/
    ├── 0001-ui-technology.md
    ├── 0002-core-language.md
    ├── 0003-swift-rust-bridge.md
    ├── 0004-local-persistence.md
    ├── 0005-secret-storage.md
    ├── 0006-distribution-model.md
    └── 0007-database-adapter-interface.md
```

Ngoài ra, tạo:

```text
AGENTS.md
README.md
CONTRIBUTING.md
SECURITY.md
```

Không ghi đè tài liệu hiện có khi chưa đọc và đánh giá nội dung.

---

## 16. ROADMAP BẮT BUỘC

### Milestone 0 — Discovery và Architecture

- Product specification.
- UX wireframe.
- Architecture decisions.
- Rust/Swift bridge spike.
- Database driver evaluation.
- Data grid prototype.
- SQL editor prototype.
- Distribution decision.
- Security threat model.

### Milestone 1 — Application Shell

- Window.
- Sidebar.
- Tabs.
- Settings.
- Keychain abstraction.
- Workspace persistence.
- Connection model.
- Logging.
- Error handling.

### Milestone 2 — PostgreSQL Vertical Slice

- Connection.
- Object explorer.
- Query editor.
- Query execution.
- Result grid.
- Basic editing.
- Transactions.
- Query cancellation.
- Export CSV.

### Milestone 3 — MySQL, MariaDB và SQLite

- Adapter architecture validation.
- Capability differences.
- Cross-database UX.
- Expanded integration tests.

### Milestone 4 — Professional Data Tools

- Object designer.
- Import/export.
- Data transfer.
- Schema diff.
- Data diff.
- Backup/restore.

### Milestone 5 — Modeling và Monitoring

- ER diagram.
- Reverse engineering.
- Execution plan.
- Session monitoring.
- User and role management.

### Milestone 6 — Additional Engines

- SQL Server.
- Redis.
- MongoDB.

### Milestone 7 — Automation và Advanced Features

- Job engine.
- Scheduler.
- Notifications.
- Advanced modeling.

Mỗi milestone phải có:

- Goal.
- Included scope.
- Excluded scope.
- Dependencies.
- Deliverables.
- Acceptance criteria.
- Test requirements.
- Security review.
- Performance review.
- Exit criteria.

---

## 17. BACKLOG FORMAT

Mỗi backlog item phải theo mẫu:

```text
ID:
Title:
Epic:
Priority:
Complexity:
Dependencies:
User story:
Description:
Technical notes:
Security considerations:
Acceptance criteria:
Tests required:
Out of scope:
Definition of done:
```

Không tạo các task chung chung như:

- “Implement database”.
- “Build UI”.
- “Add tests”.
- “Fix bugs”.

Task phải đủ nhỏ để một agent hoặc developer có thể thực hiện, kiểm thử và review độc lập.

---

## 18. RỦI RO PHẢI PHÂN TÍCH

Ít nhất phải phân tích:

- Phạm vi sản phẩm quá lớn.
- Khác biệt SQL dialect.
- Khác biệt database metadata.
- Driver licensing.
- Oracle client distribution.
- SQL Server authentication trên macOS.
- SSH implementation.
- Certificate handling.
- Query cancellation.
- Large result memory usage.
- Editable grid correctness.
- Schema diff rename detection.
- Cross-engine type mapping.
- Backup tool packaging.
- App Sandbox.
- Background automation.
- Rust/Swift FFI complexity.
- UI performance.
- ER graph layout.
- Destructive operation safety.
- Supply-chain security.
- Long-term adapter compatibility.

Với mỗi rủi ro, ghi:

- Probability.
- Impact.
- Detection strategy.
- Mitigation.
- Contingency.
- Owner role.

---

## 19. OPEN-SOURCE VÀ LICENSE POLICY

Trước khi đề xuất dependency, phải kiểm tra:

- License.
- Commercial-use compatibility.
- Maintenance activity.
- Security history.
- macOS support.
- Apple Silicon support.
- Binary distribution requirements.
- Transitive dependencies.
- Replacement cost.

Không sử dụng:

- GPL/AGPL dependency trong sản phẩm đóng nguồn nếu chưa có quyết định pháp lý rõ ràng.
- Package không được bảo trì.
- Binary không rõ nguồn gốc.
- Source code sao chép từ sản phẩm thương mại.
- Private API của macOS.

Tạo bảng dependency candidates kèm license và risk.

---

## 20. CÁC QUYẾT ĐỊNH CẦN ĐƯA RA

Trong kết quả cuối, phải đưa ra đề xuất cụ thể cho:

1. Swift-only hay Swift + Rust.
2. SwiftUI/AppKit hay Tauri/Electron.
3. SQL editor engine.
4. Data grid implementation.
5. Database driver strategy.
6. Metadata normalization.
7. Swift/Rust bridge.
8. Local persistence.
9. Keychain storage.
10. SSH implementation.
11. TLS implementation.
12. Direct distribution hay Mac App Store.
13. Auto-update.
14. Background automation.
15. Test database infrastructure.
16. Feature flags.
17. Plugin readiness.
18. Crash reporting.
19. Telemetry.
20. Licensing strategy.

Mỗi quyết định phải ghi:

- Options considered.
- Recommended option.
- Reasons.
- Trade-offs.
- Risks.
- Revisit conditions.

---

## 21. ĐỊNH DẠNG KẾT QUẢ CUỐI CÙNG

Trả lời theo thứ tự:

### A. Repository Assessment

- Repository hiện có gì.
- Thiếu gì.
- Constraint nào được phát hiện.
- File nào đã đọc.
- Lệnh nào đã chạy.

### B. Executive Summary

- Kiến trúc đề xuất.
- Phạm vi MVP.
- Thứ tự ưu tiên.
- Các rủi ro lớn nhất.

### C. Feature Matrix

Phân loại toàn bộ feature theo phase.

### D. Architecture

- Module diagram.
- Data flow.
- Concurrency model.
- Database adapter model.
- Security boundaries.
- Swift/Rust boundary.

### E. Milestone Roadmap

Kèm dependencies và exit criteria.

### F. Backlog

Danh sách task có acceptance criteria.

### G. Technical Spikes

Liệt kê spike cần thực hiện trước khi production development.

### H. Security and Safety Review

Bao gồm credential security và destructive query protection.

### I. Testing Strategy

Bao gồm unit, integration, UI, security và performance.

### J. Risks and Unknowns

Không che giấu uncertainty.

### K. Recommended First Implementation Task

Chỉ đề xuất task đầu tiên.

Không triển khai task đó trong nhiệm vụ lập kế hoạch này.

---

## 22. NGUYÊN TẮC CUỐI CÙNG

- Planning first.
- Security by design.
- Database safety by default.
- Native macOS experience.
- Streaming instead of loading everything.
- Capability-based database adapters.
- Không sao chép sản phẩm thương mại.
- Không lưu secrets dưới dạng plaintext.
- Không chạy destructive SQL mà không có safeguard.
- Không tuyên bố tính năng hoàn thành nếu chưa có test.
- Không mở rộng scope ngoài roadmap.
- Không bỏ qua lỗi test hoặc warning nghiêm trọng.
- Không che giấu những phần chưa chắc chắn.
- Mọi đề xuất phải đủ cụ thể để có thể triển khai.
- Ưu tiên một vertical slice hoàn chỉnh hơn nhiều module dang dở.

Hãy bắt đầu bằng việc đọc toàn bộ repository và file `AGENTS.md`, sau đó lập kế hoạch. Không viết production implementation trong nhiệm vụ này.
