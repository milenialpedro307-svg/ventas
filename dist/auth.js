'use strict';
let authMode='signup',recoveryMode=false;
function storeSession(data){if(!data.access_token||!data.refresh_token||!data.user?.id)throw Error('No se recibió una sesión válida.');session={...data,expires_at:Date.now()/1000+Number(data.expires_in||3600)};save('financed-auth',session)}
function showAuth(mode='signup'){
 $('#auth-loading').hidden=true;authMode=mode;connected=false;$('#bank-app').hidden=true;$('#account-hub').hidden=true;$('#auth-screen').hidden=false;
 const signup=mode==='signup',login=mode==='login',reset=mode==='reset';
 $('#auth-username-field').hidden=!signup;$('#auth-username').required=signup;$('#auth-name-field').hidden=!signup;$('#auth-name').required=signup;$('#auth-email-field').hidden=reset;$('#auth-email').required=!reset;
 $('#auth-password-field').hidden=mode==='recover';$('#auth-password').required=mode!=='recover';$('#auth-password').minLength=login?1:8;$('#auth-password').autocomplete=login?'current-password':'new-password';
 $('#auth-confirm-field').hidden=!(signup||reset);$('#auth-confirm').required=signup||reset;
 $('#auth-password').value='';$('#auth-confirm').value='';$('#forgot-password').hidden=!login;
 $('#tab-signup').classList.toggle('selected',signup);$('#tab-login').classList.toggle('selected',login);
 $('.auth-tabs').hidden=reset;$('#auth-title').textContent=signup?'Abre tu cuenta Financed.':login?'Iniciar sesión.':reset?'Tu nueva contraseña.':'Recupera tu acceso.';
 $('#auth-eyebrow').textContent=signup?'TU PRIMER PASO':login?'BIENVENIDO DE NUEVO':'TU CUENTA FINANCED';
 $('#auth-intro').textContent=signup?'Crea tu perfil y empieza a transferir.':login?'Ingresa a tu cuenta para continuar.':reset?'Elige una contraseña de al menos 8 caracteres.':'Te enviaremos un enlace a tu correo.';
 $('#auth-submit').textContent=signup?'Crear mi cuenta':login?'Iniciar sesión':reset?'Guardar contraseña':'Enviar enlace';
 $('#auth-error').textContent='';$('#auth-message').hidden=true;$('#auth-preview').hidden=reset;
}
function authNotice(message){$('#auth-message').textContent=message;$('#auth-message').hidden=false}
function enterBank(){$('#auth-loading').hidden=true;$('#auth-screen').hidden=true;$('#account-hub').hidden=true;$('#bank-app').hidden=false;render()}
async function afterLogin(){
 await ensureAuth();if(session.user.is_anonymous)throw Error('Inicia sesión con correo y contraseña.');
 const data=await rpc('state');
 if(data.account){state=data;connected=true;lastSync=Date.now();enterBank();navigate('overview');return}
 const username=session.user.user_metadata?.username;
 if(username){try{await rpc('open',{p_username:username});await sync();enterBank();navigate('overview');return}catch(e){usernameSetup(e.message);return}}
 usernameSetup();
}
function usernameSetup(message=''){$('#auth-loading').hidden=true;$('#auth-screen').hidden=true;$('#bank-app').hidden=true;$('#account-hub').hidden=false;$('#new-username').value=session.user.user_metadata?.username||'';$('#username-error').textContent=message}
$('#username-form').onsubmit=e=>{e.preventDefault();run(async()=>{try{await rpc('open',{p_username:$('#new-username').value.trim().toLowerCase()});await sync();enterBank();navigate('overview')}catch(e){$('#username-error').textContent=e.message;throw e}})};
function profile(){modal('Mi perfil',`<div class="receipt-row"><span>Nombre</span><b>${esc(connected?session?.user?.user_metadata?.full_name||me().name:me().name)}</b></div><div class="receipt-row"><span>Usuario</span><b>@${esc(me().username)}</b></div><div class="receipt-row"><span>Correo</span><span>${esc(connected?session?.user?.email||'':'Vista previa')}</span></div><div class="receipt-row"><span>Cuenta</span><b>${esc($('#card-code').textContent)}</b></div><div class="modal-actions"><button class="outline" id="profile-close">Volver</button><button class="primary" id="profile-logout">${session?'Cerrar sesión':'Crear mi cuenta'}</button></div>`);$('#profile-close').onclick=close;$('#profile-logout').onclick=()=>run(async()=>{close();if(session)await logout();else showAuth('signup')})}
async function logout(){try{if(config&&session)await request('/auth/v1/logout',{})}catch{}session=null;connected=false;save('financed-auth',null);showAuth('login');toast('Sesión cerrada')}
function terms(){modal('Condiciones de uso',`<p>Financed es una experiencia de simulación para grupos privados. Los saldos y movimientos existen únicamente dentro de la aplicación y no representan dinero depositado ni transferencias a bancos.</p><p>Las cuentas se identifican por correo y nombre de usuario. La verificación de identidad es una práctica con documentos ficticios: no valida identidades ni guarda o envía imágenes. Financed no presta servicios financieros.</p><button class="primary full" id="terms-close">Entendido</button>`);$('#terms-close').onclick=close}
$('#auth-terms').onclick=terms;$('#app-terms').onclick=terms;
$('#tab-signup').onclick=()=>showAuth('signup');$('#tab-login').onclick=()=>showAuth('login');$('#forgot-password').onclick=()=>showAuth('recover');
$('#toggle-password').onclick=()=>{const input=$('#auth-password'),show=input.type==='password';input.type=show?'text':'password';$('#toggle-password').textContent=show?'Ocultar':'Mostrar';$('#toggle-password').setAttribute('aria-label',show?'Ocultar contraseña':'Mostrar contraseña')};
$('#auth-preview').onclick=()=>{$('#auth-password').value='';$('#auth-confirm').value='';connected=false;state=demo();enterBank();navigate('overview')};
$('#hub-logout').onclick=()=>run(logout);
$('#auth-form').onsubmit=e=>{e.preventDefault();run(async()=>{
 $('#auth-error').textContent='';$('#auth-message').hidden=true;
 try{
  const email=$('#auth-email').value.trim(),password=$('#auth-password').value,fullName=$('#auth-name').value.trim();
  if((authMode==='signup'||authMode==='reset')&&password!==$('#auth-confirm').value)throw Error('Las contraseñas no coinciden.');
  if(authMode==='signup'&&!fullName)throw Error('Ingresa tu nombre y apellido.');
  const username=$('#auth-username').value.trim().toLowerCase();if(authMode==='signup'&&!/^[a-z0-9_]{3,20}$/.test(username))throw Error('El nombre de usuario debe tener 3–20 letras, números o guion bajo.');
  if(!config)throw Error('El registro estará disponible al conectar Supabase. Puedes explorar la experiencia mientras tanto.');
  const redirect=location.origin+location.pathname;
  if(authMode==='recover'){
   await request('/auth/v1/recover?redirect_to='+encodeURIComponent(redirect),{email},false);
   authNotice('Si hay una cuenta asociada a ese correo, recibirás un enlace para recuperar el acceso.');return;
  }
  if(authMode==='reset'){
   await ensureAuth();const response=await fetch(config.url+'/auth/v1/user',{method:'PUT',headers:{apikey:config.key,Authorization:'Bearer '+session.access_token,'Content-Type':'application/json'},body:JSON.stringify({password})});const data=await response.json();if(!response.ok)throw Error(data.msg||data.message||'No se pudo guardar la contraseña.');session.user=data;save('financed-auth',session);recoveryMode=false;await afterLogin();toast('Contraseña actualizada');return;
  }
  const data=authMode==='signup'?await request('/auth/v1/signup?redirect_to='+encodeURIComponent(redirect),{email,password,data:{full_name:fullName,username}},false):await request('/auth/v1/token?grant_type=password',{email,password},false);
  if(authMode==='signup'){
   showAuth('login');$('#auth-email').value=email;
   authNotice(data.access_token?'Cuenta creada. Inicia sesión con tu correo y contraseña.':'Registro recibido. El acceso aún requiere activación por el administrador.');
   $('#auth-password').focus();return;
  }
  if(!data.access_token)throw Error('No se recibió una sesión válida. Intenta iniciar sesión nuevamente.');
  storeSession(data);$('#auth-password').value='';$('#auth-confirm').value='';await afterLogin();
 }catch(e){const translations={'Invalid login credentials':'El correo o la contraseña no son correctos.','Email not confirmed':'El acceso aún no está habilitado para esta cuenta. Contacta al administrador.','User already registered':'Ya existe una cuenta con ese correo. Inicia sesión.','Invalid Refresh Token: Refresh Token Not Found':'Tu sesión venció. Inicia sesión nuevamente.'};$('#auth-error').textContent=translations[e.message]||e.message;throw e}
})};
async function bootstrap(){
 const fragment=new URLSearchParams(location.hash.slice(1));
 if(fragment.has('access_token')){
  if(!config){showAuth('login');authNotice('La conexión de Financed no está disponible. Intenta nuevamente más tarde.');return}
  try{
   const token=fragment.get('access_token');const response=await fetch(config.url+'/auth/v1/user',{headers:{apikey:config.key,Authorization:'Bearer '+token}});const user=await response.json();if(!response.ok)throw Error('El enlace de acceso ya no es válido. Solicita otro.');
   storeSession({access_token:token,refresh_token:fragment.get('refresh_token'),expires_in:Number(fragment.get('expires_in')||3600),user});history.replaceState(null,'',location.pathname+location.search);recoveryMode=fragment.get('type')==='recovery';if(recoveryMode){showAuth('reset');return}
  }catch(e){showAuth('login');authNotice(e.message);return}
 }
 if(fragment.has('error_description')){showAuth('login');authNotice(fragment.get('error_description'));history.replaceState(null,'',location.pathname+location.search);return}
 if(config&&session&&!session.user?.is_anonymous){try{await afterLogin()}catch(e){showAuth('login');authNotice('No pudimos abrir tu cuenta. '+e.message)}return}
 showAuth('signup');
}
bootstrap().catch(()=>{showAuth('login');authNotice('No pudimos abrir tu cuenta. Intenta iniciar sesión nuevamente.')});
