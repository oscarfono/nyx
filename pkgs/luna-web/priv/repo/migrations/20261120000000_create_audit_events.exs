defmodule LunaWeb.Repo.Migrations.CreateAuditEvents do
  use Ecto.Migration

  # The trigger stops a fault in the app. It does not stop an attacker who
  # has the role luna_web, because the owner of a table can drop a trigger.
  def up do
    execute """
    CREATE TABLE audit_events (
      id bigserial PRIMARY KEY,
      time timestamptz NOT NULL DEFAULT now(),
      event text NOT NULL,
      data jsonb NOT NULL DEFAULT '{}'
    )
    """

    execute """
    CREATE FUNCTION audit_events_refuse() RETURNS trigger LANGUAGE plpgsql AS $$
    BEGIN
      RAISE EXCEPTION 'LUNA: the audit log refuses %', TG_OP;
    END
    $$
    """

    execute """
    CREATE TRIGGER audit_events_no_change BEFORE UPDATE OR DELETE ON audit_events
    FOR EACH ROW EXECUTE FUNCTION audit_events_refuse()
    """

    execute """
    CREATE TRIGGER audit_events_no_truncate BEFORE TRUNCATE ON audit_events
    FOR EACH STATEMENT EXECUTE FUNCTION audit_events_refuse()
    """
  end

  def down do
    raise "LUNA: the audit log has no down migration."
  end
end
