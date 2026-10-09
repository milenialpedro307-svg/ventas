# Financed v3

Simulación bancaria para partidas privadas. No transfiere fondos reales ni verifica identidades reales.

## Supabase
La publicación incluye la URL del proyecto `https://htjtnvvfmcrsescnynwk.supabase.co` y su clave publishable pública. Ya no hay controles para configurar la conexión en las pantallas de usuarios.

Ejecuta `supabase/upgrade-contacts.sql` en SQL Editor. Se puede ejecutar en un proyecto nuevo o en una instalación anterior, y volver a ejecutar sin borrar datos. También se publica como `/upgrade-contacts.sql` y `/schema.sql`.

Habilita Email en Authentication, desactiva **Confirm email** en la configuración del proveedor Email para permitir registro sin confirmación, y configura Site URL y Redirect URLs con `https://financed.secret-seed-3847.chatgpt.site/`. Configura SMTP para correo de confirmación/recuperación a los destinatarios que necesites.

## Usuarios y contactos
Registro con nombre, correo, contraseña y nombre de usuario. El usuario tiene 3–20 letras ASCII, números o guion bajo, en minúsculas. La unicidad se confirma en PostgreSQL al abrir el perfil; si el nombre ya existe, se pide elegir otro. Los usuarios anteriores eligen un nombre al volver a entrar.

Cada usuario tiene una billetera, contactos propios y cuentas bancarias de práctica. La búsqueda usa el nombre de usuario exacto; no lista automáticamente otras personas y no expone sus correos ni saldos. Agregar un contacto solo lo agrega a la lista del solicitante.

Todas las cuentas nuevas comienzan con saldo 0, incluida la vista previa. No se importan saldos anteriores al crear un perfil. Las tablas anteriores quedan intactas; el historial anterior permanece en sus tablas originales. El esquema actual muestra su propio historial. Para poner en cero las cuentas ya existentes, ejecutar UNA SOLA VEZ `supabase/reset-balances.sql` después de la actualización; conserva el historial, pero reinicia los saldos.

## Mi banco y documento de práctica
Se elige banco, tipo y número de cuenta inventado. La cuenta de destino se guarda en Supabase para el titular autenticado. Una transferencia a BancoEstado u otro destino abre la práctica de identidad con anverso y reverso; se puede elegir una imagen local o usar ejemplos sin documentos reales.

Imágenes JPG, PNG o WebP de hasta 5 MB por lado, mostradas mediante URLs de objeto locales. No se envían a Supabase ni a otro servidor, no se almacenan en localStorage y se liberan al cerrar o completar. No se solicita RUT ni se extraen datos del carnet. No hay OCR, biometría ni validación de identidad. El servidor no conserva un estado de identidad verificada.

Al completar ambos lados, se guarda una solicitud pendiente y se muestra «Revisión de Financed pendiente. Los retiros de esta cuenta están bloqueados». No se descuenta saldo ni se genera una transferencia. El estado se conserva al iniciar sesión en otro dispositivo. No hay aprobación automática, plazo prometido ni integración de verificación bancaria. La vista previa local permite probar destinos y el paso de documento, pero no buscar personas ni crear contactos ficticios.

## Seguridad
Esquema `financed_private` con RLS y sin acceso directo para anon/authenticated. Mantenerlo fuera de los esquemas expuestos por Data API. RPC públicas SECURITY DEFINER con search_path vacío y validación de auth.uid(), rechazando usuarios anónimos.

Transferencias con validación de saldo, montos enteros positivos, contactos existentes, bloqueo de cuentas en orden estable e idempotencia por UUID. Destinos bancarios accesibles únicamente para su titular. El RPC anterior de retiro está bloqueado en el servidor; la solicitud de revisión verifica propietario y saldo, pero no transfiere fondos ni llama a bancos.

## Verificación
- Sintaxis: `node --check dist/app.js` y `node --check dist/auth.js`.
- SQL validado en PostgreSQL temporal (PGlite): instalación/repetición, usuarios únicos, ausencia de contactos iniciales, búsqueda exacta sin balances, permisos privados, transferencias, idempotencia, sobregiros, propiedad de cuentas bancarias y rechazo de acceso anónimo.
- Interfaz: registro con usuario, ausencia de configuración, contactos vacíos, destino BancoEstado, bloqueo previo al documento y finalización con ejemplos, comprobante y saldo.
- La selección automatizada de archivos no estuvo disponible en el navegador de pruebas; los inputs de imágenes locales requieren comprobarse manualmente. La práctica con ejemplos sí se comprobó.
- Los nuevos RPC aún deben instalarse en el Supabase del propietario para probar persistencia y varios dispositivos.

Vista local: `python3 -m http.server 4173 --directory dist`.


## Publicar en GitHub y Vercel
1. Subir el contenido de esta carpeta a un repositorio de GitHub (no subir `.git`, `.env` ni claves secretas). Si subes la carpeta completa dentro de otro repo, seleccionarla como Root Directory en Vercel.
2. En Vercel: Add New → Project → importar ese repositorio. Preset Other, sin comandos de instalación/build y Output Directory `dist`. `vercel.json` ya configura estos valores.
3. Publicar y copiar la URL de producción. En Supabase → Authentication → URL Configuration, usar esa URL como Site URL y agregarla con `/` a Redirect URLs para confirmación y recuperación. La app usa el origen actual del navegador para los enlaces de autenticación.
4. Ejecutar `supabase/upgrade-contacts.sql` en Supabase SQL Editor. Si quieren reiniciar todos los saldos existentes, ejecutar también `supabase/reset-balances.sql` una sola vez.

La URL de Vercel puede abrirse desde cualquier dispositivo con internet; los usuarios ingresan con su cuenta y comparten datos a través de Supabase. La clave `publishable` de `dist/config.js` es pública; nunca poner una clave `service_role` o `secret` allí. No hay mecanismo de recarga implementado: con saldo cero, no se puede transferir hasta asignar dinero de juego desde la administración de Supabase.

Después del registro, la app vuelve a Iniciar sesión, conserva el correo y borra las contraseñas del formulario. No guarda la sesión emitida al registrarse. Si Supabase sigue exigiendo confirmación, muestra que el acceso requiere activación; cambiar el texto por sí solo no desactiva el requisito del servidor.

Para actualizar una base ya instalada, ejecutar `supabase/upgrade-bank-review.sql` en SQL Editor antes de publicar los archivos. No reinicia saldos ni borra historial. La instalación completa en `upgrade-contacts.sql` también incluye este cambio. Las fotos siguen solo en el dispositivo y no se adjuntan a la solicitud.
