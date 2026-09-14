-- Run from the repository root after exporting with -JsonExportPath .\items-json.
-- This view keeps the item-level metadata and the original nested fields/tags.
CREATE OR REPLACE VIEW items AS
SELECT
    id,
    title,
    category,
    created_at,
    updated_at,
    vault.id AS vault_id,
    vault.name AS vault_name,
    tags,
    fields,
    filename AS source_file
FROM read_json_auto('items-json/*.json', union_by_name = true, filename = true);
