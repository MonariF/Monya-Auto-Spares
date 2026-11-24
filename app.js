const fmt = n => new Intl.NumberFormat("en-KE",{style:"currency",currency:"KES"}).format(n);
document.getElementById("todayLabel").textContent = new Intl.DateTimeFormat("en-KE",{weekday:"short",day:"numeric",month:"short",year:"numeric"}).format(new Date());
document.getElementById("year").textContent = new Date().getFullYear();
document.getElementById("salesTotal").textContent = fmt(0);
document.getElementById("profitTotal").textContent = fmt(0);
function connection(){
  const el=document.getElementById("connectionStatus");
  el.textContent=navigator.onLine?"● Online":"● Offline";
  el.style.color=navigator.onLine?"#b8e5c8":"#ffd28a";
}
window.addEventListener("online",connection);
window.addEventListener("offline",connection);
connection();
if("serviceWorker" in navigator && location.protocol.startsWith("http")){
  window.addEventListener("load",()=>navigator.serviceWorker.register("./service-worker.js").catch(()=>{}));
}