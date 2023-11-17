
##Restart / start again replication because of network failure.
#On BIDS side
1. Disable subscription 
select pglogical.alter_subscription_disable('tenant_service', true);

2. Drop subscription
select pglogical.drop_subscription('tenant_service',true);

3. Truncate tables
truncate table tenant_service.tenants cascade;

4. Apply not null constriants
alter table tenant_service.tenants alter column idempotency_key drop not null;
alter table tenant_service.tenants alter column trace_id drop not null;
alter table tenant_service.tenants_label_history alter column idempotency_key drop not null;
alter table tenant_service.tenants_label_history alter column trace_id drop not null;

4. Create subscription
select pglogical.create_subscription(subscription_name := 'tenant_service', provider_dsn := 'host=banking-int.cluster-cb5ytt5zm3va.eu-central-1.rds.amazonaws.com port=5432 user=thedock dbname=partner-ehotel password=Password123!', replication_sets := array['tenant_service'], synchronize_structure := false, synchronize_data := true);