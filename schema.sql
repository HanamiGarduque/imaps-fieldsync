


SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


CREATE SCHEMA IF NOT EXISTS "public";


ALTER SCHEMA "public" OWNER TO "pg_database_owner";


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE OR REPLACE FUNCTION "public"."clear_own_activity"() RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  deleted_count integer;
begin
  delete from public.activity_log
  where inspector_id = auth.uid();

  get diagnostics deleted_count = row_count;
  return deleted_count;
end;
$$;


ALTER FUNCTION "public"."clear_own_activity"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."delete_own_activity"("p_id" "uuid") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  delete from public.activity_log
  where id = p_id
    and inspector_id = auth.uid();

  return found;
end;
$$;


ALTER FUNCTION "public"."delete_own_activity"("p_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."distance_to_parcel_boundary"("parcel_id" "uuid", "lat" double precision, "lng" double precision) RETURNS double precision
    LANGUAGE "sql" STABLE
    AS $$
  select ST_Distance(
    ST_SetSRID(ST_MakePoint(lng, lat), 4326)::geography,
    geom::geography
  )
  from supabase_parcels
  where id = parcel_id;
$$;


ALTER FUNCTION "public"."distance_to_parcel_boundary"("parcel_id" "uuid", "lat" double precision, "lng" double precision) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."handle_assignment_update"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
  new.updated_at = now();
  return new;
end;
$$;


ALTER FUNCTION "public"."handle_assignment_update"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."handle_new_user"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
begin
  insert into public.profiles (id, full_name, role)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', 'Unnamed User'),
    coalesce(new.raw_user_meta_data->>'role', 'inspector')
  );
  return new;
end;
$$;


ALTER FUNCTION "public"."handle_new_user"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."log_security_event"("p_event_type" "text", "p_device_id" "text" DEFAULT NULL::"text", "p_severity" "text" DEFAULT 'info'::"text", "p_metadata" "jsonb" DEFAULT '{}'::"jsonb") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    INSERT INTO public.security_audit_logs (
        inspector_id,
        device_id,
        event_type,
        severity,
        metadata,
        occurred_at
    ) VALUES (
        auth.uid(),
        p_device_id,
        p_event_type,
        p_severity,
        p_metadata,
        now()
    );
END;
$$;


ALTER FUNCTION "public"."log_security_event"("p_event_type" "text", "p_device_id" "text", "p_severity" "text", "p_metadata" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_updated_at_utc"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  NEW.updated_at = timezone('utc', now());
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."set_updated_at_utc"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."sync_parcel_latlng"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
  new.latitude := ST_Y(new.geom::geometry);
  new.longitude := ST_X(new.geom::geometry);
  return new;
end;
$$;


ALTER FUNCTION "public"."sync_parcel_latlng"() OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."activity_log" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "inspector_id" "uuid" NOT NULL,
    "field_job_id" "uuid",
    "event_type" "text" NOT NULL,
    "title" "text" NOT NULL,
    "subtitle" "text",
    "occurred_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "is_read" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."activity_log" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."application_status_tracks" (
    "id" bigint NOT NULL,
    "reference_number" "text" NOT NULL,
    "masked_applicant_name" "text" NOT NULL,
    "status" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "cert_type" "text",
    "stage_order" integer,
    "note" "text"
);


ALTER TABLE "public"."application_status_tracks" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."application_status_tracks_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."application_status_tracks_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."application_status_tracks_id_seq" OWNED BY "public"."application_status_tracks"."id";



CREATE TABLE IF NOT EXISTS "public"."field_job_photos" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "field_job_id" "uuid" NOT NULL,
    "photo_url" "text" NOT NULL,
    "latitude" double precision,
    "longitude" double precision,
    "captured_at" timestamp with time zone DEFAULT "now"(),
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."field_job_photos" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."field_jobs" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "local_inspection_id" integer NOT NULL,
    "supabase_application_id" "uuid",
    "status" character varying(50) DEFAULT 'assigned'::character varying NOT NULL,
    "scheduled_date" "date" NOT NULL,
    "findings" "text",
    "is_compliant" boolean,
    "remarks" "text",
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "assigned_inspector_id" "uuid",
    "supabase_parcel_id" "uuid",
    "inspection_result" "text",
    "observations" "text",
    "discrepancies" "text",
    "recommendations" "text",
    "inspector_notes" "text",
    "checklist_data" "jsonb",
    "checklist_completed_count" integer DEFAULT 0,
    "checklist_total_count" integer DEFAULT 0,
    "photo_paths" "text"[],
    "photo_count" integer DEFAULT 0,
    "submitted_at" timestamp with time zone,
    "confirmed_latitude" double precision,
    "confirmed_longitude" double precision,
    "gps_accuracy_m" double precision,
    "gps_confirmed_at" timestamp with time zone,
    "deadline_date" "date",
    "is_self_scheduled" boolean DEFAULT false NOT NULL,
    "current_step" integer DEFAULT 0 NOT NULL,
    "started_at" timestamp with time zone,
    CONSTRAINT "field_jobs_inspection_result_check" CHECK (("inspection_result" = ANY (ARRAY['Compliant'::"text", 'For Review'::"text", 'With Discrepancy'::"text", 'Requires Reinspection'::"text"])))
);


ALTER TABLE "public"."field_jobs" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."inspector_device_subscriptions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "inspector_id" "uuid" NOT NULL,
    "device_token" "text" NOT NULL,
    "platform" "text" DEFAULT 'android'::"text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."inspector_device_subscriptions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."inspector_devices" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "inspector_id" "uuid" NOT NULL,
    "device_id" "text" NOT NULL,
    "platform" "text" DEFAULT 'android'::"text" NOT NULL,
    "device_model" "text",
    "biometric_enabled" boolean DEFAULT false NOT NULL,
    "biometric_type" "text",
    "is_trusted" boolean DEFAULT true NOT NULL,
    "last_login_at" timestamp with time zone DEFAULT "now"(),
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."inspector_devices" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."local_inspections" (
    "id" "text" NOT NULL,
    "actual_land_use" "text",
    "notes" "text",
    "is_compliant" integer,
    "inspection_result" "text",
    "checklist_json" "text",
    "boundary_status" "text",
    "current_step" integer DEFAULT 0,
    "is_synced" integer DEFAULT 0,
    "updated_at" "text"
);


ALTER TABLE "public"."local_inspections" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."notification_subscriptions" (
    "id" bigint NOT NULL,
    "reference_number" "text" NOT NULL,
    "device_token" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."notification_subscriptions" OWNER TO "postgres";


ALTER TABLE "public"."notification_subscriptions" ALTER COLUMN "id" ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME "public"."notification_subscriptions_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."profiles" (
    "id" "uuid" NOT NULL,
    "full_name" "text" NOT NULL,
    "role" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "phone_number" "text",
    "avatar_url" "text",
    CONSTRAINT "profiles_role_check" CHECK (("role" = ANY (ARRAY['admin'::"text", 'inspector'::"text"])))
);


ALTER TABLE "public"."profiles" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."push_device_subscriptions" (
    "id" bigint NOT NULL,
    "reference_number" "text" NOT NULL,
    "device_token" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."push_device_subscriptions" OWNER TO "postgres";


ALTER TABLE "public"."push_device_subscriptions" ALTER COLUMN "id" ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME "public"."push_device_subscriptions_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."security_audit_logs" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "inspector_id" "uuid" NOT NULL,
    "device_id" "text",
    "event_type" "text" NOT NULL,
    "severity" "text" DEFAULT 'info'::"text" NOT NULL,
    "metadata" "jsonb" DEFAULT '{}'::"jsonb",
    "ip_address" "text",
    "occurred_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."security_audit_logs" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."supabase_parcels" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "local_parcel_id" integer NOT NULL,
    "supabase_application_id" "uuid",
    "parcel_code" character varying(100),
    "lot_number" character varying(100),
    "tct_number" character varying(100),
    "tax_dec_number" character varying(100),
    "lot_area_sqm" numeric(12,4),
    "land_use_class" character varying(150),
    "property_index_number" character varying(100),
    "geom" "public"."geometry"(Geometry,4326) NOT NULL,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "latitude" double precision,
    "longitude" double precision
);


ALTER TABLE "public"."supabase_parcels" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."supabase_zoning_applications" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "local_application_id" integer NOT NULL,
    "reference_number" character varying(100) NOT NULL,
    "application_type" character varying(150) NOT NULL,
    "land_use_class" character varying(150),
    "applicant_name" character varying(255) NOT NULL,
    "representative_name" character varying(255),
    "contact_number" character varying(100),
    "email" character varying(255),
    "purpose" "text",
    "barangay" character varying(150),
    "location" "public"."geometry"(Point,4326),
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL
);


ALTER TABLE "public"."supabase_zoning_applications" OWNER TO "postgres";


ALTER TABLE ONLY "public"."application_status_tracks" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."application_status_tracks_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."activity_log"
    ADD CONSTRAINT "activity_log_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."application_status_tracks"
    ADD CONSTRAINT "application_status_tracks_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."field_job_photos"
    ADD CONSTRAINT "field_job_photos_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."field_jobs"
    ADD CONSTRAINT "field_jobs_local_inspection_id_key" UNIQUE ("local_inspection_id");



ALTER TABLE ONLY "public"."field_jobs"
    ADD CONSTRAINT "field_jobs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."inspector_device_subscriptions"
    ADD CONSTRAINT "inspector_device_subscriptions_inspector_id_device_token_key" UNIQUE ("inspector_id", "device_token");



ALTER TABLE ONLY "public"."inspector_device_subscriptions"
    ADD CONSTRAINT "inspector_device_subscriptions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."inspector_devices"
    ADD CONSTRAINT "inspector_devices_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."local_inspections"
    ADD CONSTRAINT "local_inspections_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."notification_subscriptions"
    ADD CONSTRAINT "notification_subscriptions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."notification_subscriptions"
    ADD CONSTRAINT "notification_subscriptions_reference_number_device_token_key" UNIQUE ("reference_number", "device_token");



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."push_device_subscriptions"
    ADD CONSTRAINT "push_device_subscriptions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."push_device_subscriptions"
    ADD CONSTRAINT "push_device_subscriptions_ref_token_key" UNIQUE ("reference_number", "device_token");



ALTER TABLE ONLY "public"."security_audit_logs"
    ADD CONSTRAINT "security_audit_logs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."supabase_parcels"
    ADD CONSTRAINT "supabase_parcels_local_parcel_id_key" UNIQUE ("local_parcel_id");



ALTER TABLE ONLY "public"."supabase_parcels"
    ADD CONSTRAINT "supabase_parcels_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."supabase_zoning_applications"
    ADD CONSTRAINT "supabase_zoning_applications_local_application_id_key" UNIQUE ("local_application_id");



ALTER TABLE ONLY "public"."supabase_zoning_applications"
    ADD CONSTRAINT "supabase_zoning_applications_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."application_status_tracks"
    ADD CONSTRAINT "unique_ref_status" UNIQUE ("reference_number", "status");



ALTER TABLE ONLY "public"."inspector_devices"
    ADD CONSTRAINT "uq_inspector_device" UNIQUE ("inspector_id", "device_id");



CREATE INDEX "activity_log_inspector_occurred_idx" ON "public"."activity_log" USING "btree" ("inspector_id", "occurred_at" DESC);



CREATE INDEX "application_status_tracks_reference_number_idx" ON "public"."application_status_tracks" USING "btree" ("reference_number");



CREATE INDEX "idx_field_job_photos_job_id" ON "public"."field_job_photos" USING "btree" ("field_job_id");



CREATE INDEX "idx_field_jobs_app_id" ON "public"."field_jobs" USING "btree" ("supabase_application_id");



CREATE INDEX "idx_field_jobs_inspector_status" ON "public"."field_jobs" USING "btree" ("assigned_inspector_id", "status");



CREATE INDEX "idx_field_jobs_status" ON "public"."field_jobs" USING "btree" ("status");



CREATE INDEX "idx_inspector_devices_user_device" ON "public"."inspector_devices" USING "btree" ("inspector_id", "device_id");



CREATE INDEX "idx_parcels_app_id" ON "public"."supabase_parcels" USING "btree" ("supabase_application_id");



CREATE INDEX "idx_parcels_geom" ON "public"."supabase_parcels" USING "gist" ("geom");



CREATE INDEX "idx_security_audit_inspector" ON "public"."security_audit_logs" USING "btree" ("inspector_id", "occurred_at" DESC);



CREATE INDEX "idx_status_tracks_ref_no" ON "public"."application_status_tracks" USING "btree" ("reference_number");



CREATE INDEX "idx_zoning_apps_location" ON "public"."supabase_zoning_applications" USING "gist" ("location");



CREATE INDEX "push_device_subscriptions_reference_number_idx" ON "public"."push_device_subscriptions" USING "btree" ("reference_number");



CREATE OR REPLACE TRIGGER "notify-on-status-change" AFTER INSERT ON "public"."application_status_tracks" FOR EACH ROW EXECUTE FUNCTION "public"."send_push_notification_webhook"();



CREATE OR REPLACE TRIGGER "on_assignment_change" AFTER INSERT ON "public"."field_jobs" FOR EACH ROW EXECUTE FUNCTION "public"."send_push_notification_webhook"();



CREATE OR REPLACE TRIGGER "trg_field_jobs_set_updated_at" BEFORE UPDATE ON "public"."field_jobs" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at_utc"();



CREATE OR REPLACE TRIGGER "trg_sync_parcel_latlng" BEFORE INSERT OR UPDATE OF "geom" ON "public"."supabase_parcels" FOR EACH ROW EXECUTE FUNCTION "public"."sync_parcel_latlng"();



ALTER TABLE ONLY "public"."activity_log"
    ADD CONSTRAINT "activity_log_field_job_id_fkey" FOREIGN KEY ("field_job_id") REFERENCES "public"."field_jobs"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."activity_log"
    ADD CONSTRAINT "activity_log_inspector_id_fkey" FOREIGN KEY ("inspector_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."field_job_photos"
    ADD CONSTRAINT "field_job_photos_field_job_id_fkey" FOREIGN KEY ("field_job_id") REFERENCES "public"."field_jobs"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."field_jobs"
    ADD CONSTRAINT "field_jobs_assigned_inspector_id_fkey" FOREIGN KEY ("assigned_inspector_id") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."field_jobs"
    ADD CONSTRAINT "field_jobs_supabase_application_id_fkey" FOREIGN KEY ("supabase_application_id") REFERENCES "public"."supabase_zoning_applications"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."field_jobs"
    ADD CONSTRAINT "field_jobs_supabase_parcel_id_fkey" FOREIGN KEY ("supabase_parcel_id") REFERENCES "public"."supabase_parcels"("id");



ALTER TABLE ONLY "public"."inspector_device_subscriptions"
    ADD CONSTRAINT "inspector_device_subscriptions_inspector_id_fkey" FOREIGN KEY ("inspector_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."inspector_devices"
    ADD CONSTRAINT "inspector_devices_inspector_id_fkey" FOREIGN KEY ("inspector_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."security_audit_logs"
    ADD CONSTRAINT "security_audit_logs_inspector_id_fkey" FOREIGN KEY ("inspector_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."supabase_parcels"
    ADD CONSTRAINT "supabase_parcels_supabase_application_id_fkey" FOREIGN KEY ("supabase_application_id") REFERENCES "public"."supabase_zoning_applications"("id") ON DELETE CASCADE;



CREATE POLICY "Allow anonymous insert" ON "public"."push_device_subscriptions" FOR INSERT TO "anon" WITH CHECK (true);



CREATE POLICY "Allow anonymous select" ON "public"."push_device_subscriptions" FOR SELECT TO "anon" USING (true);



CREATE POLICY "Allow anonymous update" ON "public"."push_device_subscriptions" FOR UPDATE TO "anon" USING (true) WITH CHECK (true);



CREATE POLICY "Allow public delete" ON "public"."notification_subscriptions" FOR DELETE TO "anon" USING (true);



CREATE POLICY "Allow public insert" ON "public"."notification_subscriptions" FOR INSERT TO "anon" WITH CHECK (true);



CREATE POLICY "Allow public insert access" ON "public"."application_status_tracks" FOR INSERT TO "anon" WITH CHECK (true);



CREATE POLICY "Allow public read access" ON "public"."application_status_tracks" FOR SELECT TO "anon" USING (true);



CREATE POLICY "Enable read access for all users" ON "public"."field_jobs" FOR SELECT USING (true);



CREATE POLICY "InsertStatus" ON "public"."application_status_tracks" USING (true) WITH CHECK (true);



CREATE POLICY "Inspectors can insert their own security logs" ON "public"."security_audit_logs" FOR INSERT WITH CHECK (("auth"."uid"() = "inspector_id"));



CREATE POLICY "Inspectors can insert/update their own devices" ON "public"."inspector_devices" USING (("auth"."uid"() = "inspector_id")) WITH CHECK (("auth"."uid"() = "inspector_id"));



CREATE POLICY "Inspectors can update their assigned jobs" ON "public"."field_jobs" FOR UPDATE TO "authenticated" USING (("auth"."uid"() = "assigned_inspector_id")) WITH CHECK (("auth"."uid"() = "assigned_inspector_id"));



CREATE POLICY "Inspectors can view applications" ON "public"."supabase_zoning_applications" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Inspectors can view parcels" ON "public"."supabase_parcels" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Inspectors can view their own assigned jobs" ON "public"."field_jobs" FOR SELECT TO "authenticated" USING (("auth"."uid"() = "assigned_inspector_id"));



CREATE POLICY "Inspectors can view their own devices" ON "public"."inspector_devices" FOR SELECT USING (("auth"."uid"() = "inspector_id"));



CREATE POLICY "Inspectors can view their own security logs" ON "public"."security_audit_logs" FOR SELECT USING (("auth"."uid"() = "inspector_id"));



CREATE POLICY "Public read" ON "public"."application_status_tracks" FOR SELECT USING (true);



ALTER TABLE "public"."activity_log" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "admins insert field jobs" ON "public"."field_jobs" FOR INSERT TO "authenticated" WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."profiles"
  WHERE (("profiles"."id" = "auth"."uid"()) AND ("profiles"."role" = 'admin'::"text")))));



ALTER TABLE "public"."application_status_tracks" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."field_job_photos" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."field_jobs" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."inspector_device_subscriptions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."inspector_devices" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "inspectors delete own activity" ON "public"."activity_log" FOR DELETE TO "authenticated" USING (("inspector_id" = "auth"."uid"()));



CREATE POLICY "inspectors insert own activity" ON "public"."activity_log" FOR INSERT WITH CHECK (("auth"."uid"() = "inspector_id"));



CREATE POLICY "inspectors insert own job photos" ON "public"."field_job_photos" FOR INSERT TO "authenticated" WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."field_jobs"
  WHERE (("field_jobs"."id" = "field_job_photos"."field_job_id") AND ("field_jobs"."assigned_inspector_id" = "auth"."uid"())))));



CREATE POLICY "inspectors manage own device tokens" ON "public"."inspector_device_subscriptions" TO "authenticated" USING (("auth"."uid"() = "inspector_id")) WITH CHECK (("auth"."uid"() = "inspector_id"));



CREATE POLICY "inspectors update own activity" ON "public"."activity_log" FOR UPDATE USING (("auth"."uid"() = "inspector_id")) WITH CHECK (("auth"."uid"() = "inspector_id"));



CREATE POLICY "inspectors view own activity" ON "public"."activity_log" FOR SELECT USING (("auth"."uid"() = "inspector_id"));



CREATE POLICY "inspectors view own job photos" ON "public"."field_job_photos" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."field_jobs"
  WHERE (("field_jobs"."id" = "field_job_photos"."field_job_id") AND ("field_jobs"."assigned_inspector_id" = "auth"."uid"())))));



ALTER TABLE "public"."local_inspections" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."notification_subscriptions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."profiles" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."push_device_subscriptions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."security_audit_logs" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."supabase_parcels" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."supabase_zoning_applications" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "users update own profile" ON "public"."profiles" FOR UPDATE TO "authenticated" USING (("auth"."uid"() = "id")) WITH CHECK (("auth"."uid"() = "id"));



CREATE POLICY "users view own profile" ON "public"."profiles" FOR SELECT TO "authenticated" USING (("auth"."uid"() = "id"));



GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";



REVOKE ALL ON FUNCTION "public"."clear_own_activity"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."clear_own_activity"() TO "anon";
GRANT ALL ON FUNCTION "public"."clear_own_activity"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."clear_own_activity"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."delete_own_activity"("p_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."delete_own_activity"("p_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."delete_own_activity"("p_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."delete_own_activity"("p_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."distance_to_parcel_boundary"("parcel_id" "uuid", "lat" double precision, "lng" double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."distance_to_parcel_boundary"("parcel_id" "uuid", "lat" double precision, "lng" double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."distance_to_parcel_boundary"("parcel_id" "uuid", "lat" double precision, "lng" double precision) TO "service_role";



GRANT ALL ON FUNCTION "public"."handle_assignment_update"() TO "anon";
GRANT ALL ON FUNCTION "public"."handle_assignment_update"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."handle_assignment_update"() TO "service_role";



GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "anon";
GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "service_role";



GRANT ALL ON FUNCTION "public"."log_security_event"("p_event_type" "text", "p_device_id" "text", "p_severity" "text", "p_metadata" "jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."log_security_event"("p_event_type" "text", "p_device_id" "text", "p_severity" "text", "p_metadata" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."log_security_event"("p_event_type" "text", "p_device_id" "text", "p_severity" "text", "p_metadata" "jsonb") TO "service_role";



GRANT ALL ON FUNCTION "public"."set_updated_at_utc"() TO "anon";
GRANT ALL ON FUNCTION "public"."set_updated_at_utc"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_updated_at_utc"() TO "service_role";



GRANT ALL ON FUNCTION "public"."sync_parcel_latlng"() TO "anon";
GRANT ALL ON FUNCTION "public"."sync_parcel_latlng"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."sync_parcel_latlng"() TO "service_role";



GRANT ALL ON TABLE "public"."activity_log" TO "anon";
GRANT ALL ON TABLE "public"."activity_log" TO "authenticated";
GRANT ALL ON TABLE "public"."activity_log" TO "service_role";



GRANT ALL ON TABLE "public"."application_status_tracks" TO "anon";
GRANT ALL ON TABLE "public"."application_status_tracks" TO "authenticated";
GRANT ALL ON TABLE "public"."application_status_tracks" TO "service_role";



GRANT ALL ON SEQUENCE "public"."application_status_tracks_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."application_status_tracks_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."application_status_tracks_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."field_job_photos" TO "anon";
GRANT ALL ON TABLE "public"."field_job_photos" TO "authenticated";
GRANT ALL ON TABLE "public"."field_job_photos" TO "service_role";



GRANT ALL ON TABLE "public"."field_jobs" TO "anon";
GRANT ALL ON TABLE "public"."field_jobs" TO "authenticated";
GRANT ALL ON TABLE "public"."field_jobs" TO "service_role";



GRANT ALL ON TABLE "public"."inspector_device_subscriptions" TO "anon";
GRANT ALL ON TABLE "public"."inspector_device_subscriptions" TO "authenticated";
GRANT ALL ON TABLE "public"."inspector_device_subscriptions" TO "service_role";



GRANT ALL ON TABLE "public"."inspector_devices" TO "anon";
GRANT ALL ON TABLE "public"."inspector_devices" TO "authenticated";
GRANT ALL ON TABLE "public"."inspector_devices" TO "service_role";



GRANT ALL ON TABLE "public"."local_inspections" TO "anon";
GRANT ALL ON TABLE "public"."local_inspections" TO "authenticated";
GRANT ALL ON TABLE "public"."local_inspections" TO "service_role";



GRANT ALL ON TABLE "public"."notification_subscriptions" TO "anon";
GRANT ALL ON TABLE "public"."notification_subscriptions" TO "authenticated";
GRANT ALL ON TABLE "public"."notification_subscriptions" TO "service_role";



GRANT ALL ON SEQUENCE "public"."notification_subscriptions_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."notification_subscriptions_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."notification_subscriptions_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."profiles" TO "anon";
GRANT ALL ON TABLE "public"."profiles" TO "authenticated";
GRANT ALL ON TABLE "public"."profiles" TO "service_role";



GRANT ALL ON TABLE "public"."push_device_subscriptions" TO "anon";
GRANT ALL ON TABLE "public"."push_device_subscriptions" TO "authenticated";
GRANT ALL ON TABLE "public"."push_device_subscriptions" TO "service_role";



GRANT ALL ON SEQUENCE "public"."push_device_subscriptions_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."push_device_subscriptions_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."push_device_subscriptions_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."security_audit_logs" TO "anon";
GRANT ALL ON TABLE "public"."security_audit_logs" TO "authenticated";
GRANT ALL ON TABLE "public"."security_audit_logs" TO "service_role";



GRANT ALL ON TABLE "public"."supabase_parcels" TO "anon";
GRANT ALL ON TABLE "public"."supabase_parcels" TO "authenticated";
GRANT ALL ON TABLE "public"."supabase_parcels" TO "service_role";



GRANT ALL ON TABLE "public"."supabase_zoning_applications" TO "anon";
GRANT ALL ON TABLE "public"."supabase_zoning_applications" TO "authenticated";
GRANT ALL ON TABLE "public"."supabase_zoning_applications" TO "service_role";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";







