/* IDCG Tender Platform - Supabase client foundation.
 * Load supabase-js v2 before this file, then load supabase/config.js.
 * This file does not change the existing localStorage dashboard until the
 * application migration step explicitly wires it in.
 */
(function (global) {
  "use strict";

  const config = global.IDCG_SUPABASE_CONFIG || {};
  let client = null;

  function getClient() {
    if (client) return client;
    if (!global.supabase || typeof global.supabase.createClient !== "function") {
      throw new Error("Supabase JS v2 is not loaded. Load the Supabase CDN bundle first.");
    }
    if (!config.url || !config.publishableKey ||
        config.url.includes("YOUR_PROJECT_REF") ||
        config.publishableKey.includes("YOUR_SUPABASE")) {
      throw new Error("Supabase is not configured. Create supabase/config.js from config.example.js.");
    }
    client = global.supabase.createClient(config.url, config.publishableKey, {
      auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true }
    });
    return client;
  }

  async function getSession() {
    const { data, error } = await getClient().auth.getSession();
    if (error) throw error;
    return data.session;
  }
  async function signIn(email, password) {
    const { data, error } = await getClient().auth.signInWithPassword({ email, password });
    if (error) throw error;
    return data;
  }
  async function signOut() {
    const { error } = await getClient().auth.signOut();
    if (error) throw error;
  }
  async function listTenders() {
    const { data, error } = await getClient().from("tenders").select("*")
      .order("tender_date", { ascending: false, nullsFirst: false });
    if (error) throw error;
    return data || [];
  }
  async function createTender(record) {
    const { data, error } = await getClient().from("tenders").insert(record).select().single();
    if (error) throw error;
    return data;
  }
  async function updateTender(id, changes) {
    const { data, error } = await getClient().from("tenders").update(changes)
      .eq("id", id).select().single();
    if (error) throw error;
    return data;
  }
  async function deleteTender(id) {
    const { error } = await getClient().from("tenders").delete().eq("id", id);
    if (error) throw error;
  }

  global.IDCGCloud = Object.freeze({
    getClient, getSession, signIn, signOut,
    listTenders, createTender, updateTender, deleteTender
  });
})(window);
