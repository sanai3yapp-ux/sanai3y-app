import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json; charset=utf-8",
};

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, { auth: { autoRefreshToken: false, persistSession: false } });

function json(data: unknown, status = 200) { return new Response(JSON.stringify(data), { status, headers: corsHeaders }); }
function normalizeCustomerPhone(value: string) { let phone = value.trim().replace(/\s+/g, "").replace(/-/g, ""); if (phone.startsWith("+20")) phone = "0" + phone.substring(3); else if (phone.startsWith("0020")) phone = "0" + phone.substring(4); return phone; }
function isEgyptianPhone(phone: string) { return /^01\d{9}$/.test(phone); }
function internationalDigits(phone: string) { return "20" + phone.substring(1); }
function authEmailLocal(phone: string) { return `customer.${phone}@sana3y.app`; }
function authEmailLegacyInternational(phone: string) { return `customer.${internationalDigits(phone)}@sana3y.app`; }
function authEmailLegacyScreenshot(phone: string) { return `customer.${phone}@auth.sanai3y.com`; }
function authPasswordInternational(phone: string, pin: string) { return `S3_${internationalDigits(phone)}_${pin}`; }
function authPasswordLocal(phone: string, pin: string) { return `S3_${phone}_${pin}`; }

async function findCustomer(phone: string) {
  const international = `+20${phone.substring(1)}`;
  const legacy = `0020${phone.substring(1)}`;
  const { data, error } = await admin.from("customers").select("id,user_id,phone,account_status").in("phone", [phone, international, legacy]).limit(1).maybeSingle();
  if (error) throw new Error(error.message);
  return data;
}

async function actualAuthEmail(userId: string | null) {
  if (!userId) return null;
  const { data, error } = await admin.auth.admin.getUserById(userId);
  if (error || !data.user?.email) return null;
  return data.user.email.trim();
}

async function signInCustomer(phone: string, pin: string, userId: string | null) {
  const actualEmail = await actualAuthEmail(userId);
  const emails = [actualEmail, authEmailLegacyInternational(phone), authEmailLocal(phone), authEmailLegacyScreenshot(phone)].filter((v): v is string => !!v);
  const passwords = [authPasswordInternational(phone, pin), authPasswordLocal(phone, pin), pin];
  let lastError: unknown = null;
  for (const email of [...new Set(emails)]) {
    for (const password of [...new Set(passwords)]) {
      const { data, error } = await admin.auth.signInWithPassword({ email, password });
      if (!error && data.session) return data;
      lastError = error;
    }
  }
  console.error("customer sign-in failed:", lastError);
  return null;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);
  try {
    const body = await req.json();
    const action = String(body?.action ?? "").trim();
    const phone = normalizeCustomerPhone(String(body?.phone ?? ""));
    const pin = String(body?.pin ?? "");
    if (!phone || !isEgyptianPhone(phone)) return json({ error: "رقم الهاتف المصري غير صحيح." }, 400);
    if (!["check", "register", "login"].includes(action)) return json({ error: "عملية غير مدعومة." }, 400);
    if (action !== "check" && !/^\d{6}$/.test(pin)) return json({ error: "PIN يجب أن يتكون من 6 أرقام." }, 400);
    const customer = await findCustomer(phone);
    if (action === "check") return json({ exists: customer != null, blocked: customer != null && customer.account_status !== "active" });
    if (action === "login") {
      if (!customer) return json({ error: "لا يوجد حساب عميل بهذا الرقم." }, 404);
      if (customer.account_status !== "active") return json({ error: "هذا الحساب غير متاح حاليًا." }, 403);
      if (customer.phone !== phone) { const { error } = await admin.from("customers").update({ phone }).eq("id", customer.id); if (error) console.error("phone normalization failed:", error); }
      const data = await signInCustomer(phone, pin, customer.user_id);
      if (!data?.session) return json({ error: "رقم الهاتف أو PIN غير صحيح." }, 401);
      return json({ ok: true, access_token: data.session.access_token, refresh_token: data.session.refresh_token, user_id: data.user?.id ?? customer.user_id, customer_id: customer.id });
    }
    if (customer) return json({ error: "هذا الرقم لديه حساب بالفعل. استخدم تسجيل الدخول." }, 409);
    const email = authEmailLegacyInternational(phone);
    const password = authPasswordInternational(phone, pin);
    const { data: created, error: createError } = await admin.auth.admin.createUser({ email, password, email_confirm: true, user_metadata: { account_type: "customer", phone } });
    if (createError || !created.user) return json({ error: createError?.message ?? "تعذر إنشاء حساب العميل." }, 400);
    const { data: insertedCustomer, error: customerError } = await admin.from("customers").insert({ full_name: "العميل", phone, user_id: created.user.id, account_status: "active" }).select("id,user_id").single();
    if (customerError) { await admin.auth.admin.deleteUser(created.user.id); return json({ error: "تعذر إنشاء ملف العميل." }, 400); }
    const { data: sessionData, error: sessionError } = await admin.auth.signInWithPassword({ email, password });
    if (sessionError || !sessionData.session) { await admin.from("customers").delete().eq("id", insertedCustomer.id); await admin.auth.admin.deleteUser(created.user.id); return json({ error: "تم إنشاء الحساب لكن تعذر فتح الجلسة." }, 500); }
    return json({ ok: true, access_token: sessionData.session.access_token, refresh_token: sessionData.session.refresh_token, user_id: created.user.id, customer_id: insertedCustomer.id });
  } catch (error) {
    console.error("customer-auth error:", error);
    return json({ error: "حدث خطأ أثناء تنفيذ العملية. حاول مرة أخرى." }, 500);
  }
});
