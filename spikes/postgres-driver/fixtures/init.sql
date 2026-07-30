CREATE ROLE dataforge_test_client LOGIN;
CREATE ROLE dataforge_test_wrong_client LOGIN;

CREATE TABLE dataforge_transaction_probe (
    id BIGINT PRIMARY KEY,
    run_marker TEXT NOT NULL,
    note TEXT NOT NULL
);

GRANT SELECT, INSERT, UPDATE, DELETE ON dataforge_transaction_probe
    TO dataforge_test_client;
