-- Load duckdb/items.sql first. Each row references its parent item by item_id.
CREATE OR REPLACE VIEW fields AS
WITH all_fields as (
  SELECT
      i.id AS item_id,
      i.title AS item_title,
      i.vault_id,
      i.vault_name,
      i.source_file,
      field.id AS field_id,
      field.label AS field_label,
      field.type AS field_type,
      field.purpose AS field_purpose,
      from_json(
        field.section,
        '"STRUCT(id VARCHAR, label VARCHAR)"'
      ) as field_section,
      field.value as field_value
  FROM items AS i,
      UNNEST(
          from_json(
            i.fields,
            '["STRUCT(id VARCHAR, label VARCHAR, type VARCHAR, purpose VARCHAR, section VARCHAR, value VARCHAR, reference VARCHAR)"]'
          )
      ) AS unnested(field)
)

select
  item_id,
  item_title,
  vault_id,
  vault_name,
  source_file,
  field_section.id AS section_id,
  field_section.label AS section_label,
  field_id,
  field_label,
  field_type,
  field_purpose,
  field_value
from all_fields;