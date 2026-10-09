-- Ejecutar una sola vez, después de upgrade-contacts.sql.
-- Pone TODAS las cuentas actuales en cero. Conserva usuarios, contactos e historial.
begin;
update financed_private.profiles set balance = 0;
commit;
