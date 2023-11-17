##Add new table / column
1. Make not null on BIDS
alter table tenant_service.tenants_state_history alter column idempotency_key drop not null;
alter table tenant_service.tenants_state_history alter column trace_id drop not null;


2. Export replication on Production
select pglogical.replication_set_add_table(set_name := 'tenant_service', relation := 'tenant_service.tenants_state_history', synchronize_data := true, columns := '{id,tenant_id,status,inserted_at}');