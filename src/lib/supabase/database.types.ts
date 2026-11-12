export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.18"
  }
  public: {
    Tables: {
      app_settings: {
        Row: {
          description: string
          is_public: boolean
          key: string
          value: Json
        }
        Insert: {
          description: string
          is_public?: boolean
          key: string
          value: Json
        }
        Update: {
          description?: string
          is_public?: boolean
          key?: string
          value?: Json
        }
        Relationships: []
      }
      audit_log: {
        Row: {
          actor_person_id: string | null
          actor_role: string | null
          changed_fields: string[] | null
          detail: Json | null
          id: number
          occurred_at: string
          operation: string
          row_key: string
          table_name: string
        }
        Insert: {
          actor_person_id?: string | null
          actor_role?: string | null
          changed_fields?: string[] | null
          detail?: Json | null
          id?: never
          occurred_at?: string
          operation: string
          row_key: string
          table_name: string
        }
        Update: {
          actor_person_id?: string | null
          actor_role?: string | null
          changed_fields?: string[] | null
          detail?: Json | null
          id?: never
          occurred_at?: string
          operation?: string
          row_key?: string
          table_name?: string
        }
        Relationships: []
      }
      contact_reveals: {
        Row: {
          day: string
          id: number
          profile_id: string
          reveals_count: number
        }
        Insert: {
          day: string
          id?: never
          profile_id: string
          reveals_count?: number
        }
        Update: {
          day?: string
          id?: never
          profile_id?: string
          reveals_count?: number
        }
        Relationships: [
          {
            foreignKeyName: "contact_reveals_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "public_profile_cards"
            referencedColumns: ["profile_id"]
          },
          {
            foreignKeyName: "contact_reveals_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "public_profile_detail"
            referencedColumns: ["profile_id"]
          },
          {
            foreignKeyName: "contact_reveals_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "therapist_profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      contact_types: {
        Row: {
          code: string
          id: number
          is_active: boolean
          is_private: boolean
          is_required: boolean
          sort_order: number
        }
        Insert: {
          code: string
          id?: never
          is_active?: boolean
          is_private?: boolean
          is_required?: boolean
          sort_order?: number
        }
        Update: {
          code?: string
          id?: never
          is_active?: boolean
          is_private?: boolean
          is_required?: boolean
          sort_order?: number
        }
        Relationships: []
      }
      currencies: {
        Row: {
          code: string
          id: number
          is_active: boolean
          minor_units: number
          sort_order: number
        }
        Insert: {
          code: string
          id?: never
          is_active?: boolean
          minor_units: number
          sort_order?: number
        }
        Update: {
          code?: string
          id?: never
          is_active?: boolean
          minor_units?: number
          sort_order?: number
        }
        Relationships: []
      }
      erasure_fingerprints: {
        Row: {
          contact_type_id: number
          erasure_count: number
          expires_at: string
          fingerprint: string
          first_erased_at: string
          id: number
          last_erased_at: string
        }
        Insert: {
          contact_type_id: number
          erasure_count?: number
          expires_at: string
          fingerprint: string
          first_erased_at?: string
          id?: never
          last_erased_at?: string
        }
        Update: {
          contact_type_id?: number
          erasure_count?: number
          expires_at?: string
          fingerprint?: string
          first_erased_at?: string
          id?: never
          last_erased_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "erasure_fingerprints_contact_type_id_fkey"
            columns: ["contact_type_id"]
            isOneToOne: false
            referencedRelation: "contact_types"
            referencedColumns: ["id"]
          },
        ]
      }
      languages: {
        Row: {
          code: string
          id: number
          is_active: boolean
          native_name: string
          sort_order: number
        }
        Insert: {
          code: string
          id?: never
          is_active?: boolean
          native_name: string
          sort_order?: number
        }
        Update: {
          code?: string
          id?: never
          is_active?: boolean
          native_name?: string
          sort_order?: number
        }
        Relationships: []
      }
      legal_document_types: {
        Row: {
          code: string
          id: number
          is_active: boolean
          is_required: boolean
          sort_order: number
        }
        Insert: {
          code: string
          id?: never
          is_active?: boolean
          is_required: boolean
          sort_order?: number
        }
        Update: {
          code?: string
          id?: never
          is_active?: boolean
          is_required?: boolean
          sort_order?: number
        }
        Relationships: []
      }
      location_levels: {
        Row: {
          code: string
          depth: number
          id: number
          is_active: boolean
        }
        Insert: {
          code: string
          depth: number
          id?: never
          is_active?: boolean
        }
        Update: {
          code?: string
          depth?: number
          id?: never
          is_active?: boolean
        }
        Relationships: []
      }
      location_translations: {
        Row: {
          language_id: number
          location_id: number
          name: string
        }
        Insert: {
          language_id: number
          location_id: number
          name: string
        }
        Update: {
          language_id?: number
          location_id?: number
          name?: string
        }
        Relationships: [
          {
            foreignKeyName: "location_translations_language_id_fkey"
            columns: ["language_id"]
            isOneToOne: false
            referencedRelation: "languages"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "location_translations_location_id_fkey"
            columns: ["location_id"]
            isOneToOne: false
            referencedRelation: "locations"
            referencedColumns: ["id"]
          },
        ]
      }
      locations: {
        Row: {
          created_at: string
          default_currency_id: number | null
          id: number
          is_active: boolean
          iso_code: string | null
          level_id: number
          parent_id: number | null
          sort_order: number
        }
        Insert: {
          created_at?: string
          default_currency_id?: number | null
          id?: never
          is_active?: boolean
          iso_code?: string | null
          level_id: number
          parent_id?: number | null
          sort_order?: number
        }
        Update: {
          created_at?: string
          default_currency_id?: number | null
          id?: never
          is_active?: boolean
          iso_code?: string | null
          level_id?: number
          parent_id?: number | null
          sort_order?: number
        }
        Relationships: [
          {
            foreignKeyName: "locations_default_currency_id_fkey"
            columns: ["default_currency_id"]
            isOneToOne: false
            referencedRelation: "currencies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "locations_level_id_fkey"
            columns: ["level_id"]
            isOneToOne: false
            referencedRelation: "location_levels"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "locations_parent_id_fkey"
            columns: ["parent_id"]
            isOneToOne: false
            referencedRelation: "locations"
            referencedColumns: ["id"]
          },
        ]
      }
      moderation_events: {
        Row: {
          actor_person_id: string | null
          created_at: string
          id: number
          profile_id: string | null
          profile_status_id: number | null
          reason: string | null
          revision_id: string | null
          revision_status_id: number | null
        }
        Insert: {
          actor_person_id?: string | null
          created_at?: string
          id?: never
          profile_id?: string | null
          profile_status_id?: number | null
          reason?: string | null
          revision_id?: string | null
          revision_status_id?: number | null
        }
        Update: {
          actor_person_id?: string | null
          created_at?: string
          id?: never
          profile_id?: string | null
          profile_status_id?: number | null
          reason?: string | null
          revision_id?: string | null
          revision_status_id?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "moderation_events_actor_person_id_fkey"
            columns: ["actor_person_id"]
            isOneToOne: false
            referencedRelation: "people"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "moderation_events_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "public_profile_cards"
            referencedColumns: ["profile_id"]
          },
          {
            foreignKeyName: "moderation_events_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "public_profile_detail"
            referencedColumns: ["profile_id"]
          },
          {
            foreignKeyName: "moderation_events_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "therapist_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "moderation_events_profile_status_id_fkey"
            columns: ["profile_status_id"]
            isOneToOne: false
            referencedRelation: "profile_statuses"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "moderation_events_revision_id_fkey"
            columns: ["revision_id"]
            isOneToOne: false
            referencedRelation: "profile_revisions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "moderation_events_revision_status_id_fkey"
            columns: ["revision_status_id"]
            isOneToOne: false
            referencedRelation: "revision_statuses"
            referencedColumns: ["id"]
          },
        ]
      }
      people: {
        Row: {
          auth_user_id: string | null
          created_at: string
          email: string | null
          erased_at: string | null
          full_name: string
          id: string
        }
        Insert: {
          auth_user_id?: string | null
          created_at?: string
          email?: string | null
          erased_at?: string | null
          full_name: string
          id?: string
        }
        Update: {
          auth_user_id?: string | null
          created_at?: string
          email?: string | null
          erased_at?: string | null
          full_name?: string
          id?: string
        }
        Relationships: []
      }
      person_roles: {
        Row: {
          created_at: string
          person_id: string
          role_id: number
        }
        Insert: {
          created_at?: string
          person_id: string
          role_id: number
        }
        Update: {
          created_at?: string
          person_id?: string
          role_id?: number
        }
        Relationships: [
          {
            foreignKeyName: "person_roles_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "people"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "person_roles_role_id_fkey"
            columns: ["role_id"]
            isOneToOne: false
            referencedRelation: "roles"
            referencedColumns: ["id"]
          },
        ]
      }
      profile_contacts: {
        Row: {
          accepts_whatsapp: boolean
          contact_type_id: number
          profile_id: string
          value: string
        }
        Insert: {
          accepts_whatsapp?: boolean
          contact_type_id: number
          profile_id: string
          value: string
        }
        Update: {
          accepts_whatsapp?: boolean
          contact_type_id?: number
          profile_id?: string
          value?: string
        }
        Relationships: [
          {
            foreignKeyName: "profile_contacts_contact_type_id_fkey"
            columns: ["contact_type_id"]
            isOneToOne: false
            referencedRelation: "contact_types"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "profile_contacts_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "public_profile_cards"
            referencedColumns: ["profile_id"]
          },
          {
            foreignKeyName: "profile_contacts_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "public_profile_detail"
            referencedColumns: ["profile_id"]
          },
          {
            foreignKeyName: "profile_contacts_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "therapist_profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      profile_languages: {
        Row: {
          language_id: number
          profile_id: string
        }
        Insert: {
          language_id: number
          profile_id: string
        }
        Update: {
          language_id?: number
          profile_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "profile_languages_language_id_fkey"
            columns: ["language_id"]
            isOneToOne: false
            referencedRelation: "languages"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "profile_languages_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "public_profile_cards"
            referencedColumns: ["profile_id"]
          },
          {
            foreignKeyName: "profile_languages_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "public_profile_detail"
            referencedColumns: ["profile_id"]
          },
          {
            foreignKeyName: "profile_languages_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "therapist_profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      profile_revisions: {
        Row: {
          closed_at: string | null
          created_at: string
          decided_at: string | null
          due_at: string | null
          flagged_terms: string[]
          id: string
          is_priority: boolean
          payload: Json
          profile_id: string
          rejection_reason: string | null
          status_id: number
          submitted_at: string | null
          suggested_therapy: string | null
        }
        Insert: {
          closed_at?: string | null
          created_at?: string
          decided_at?: string | null
          due_at?: string | null
          flagged_terms?: string[]
          id?: string
          is_priority?: boolean
          payload: Json
          profile_id: string
          rejection_reason?: string | null
          status_id: number
          submitted_at?: string | null
          suggested_therapy?: string | null
        }
        Update: {
          closed_at?: string | null
          created_at?: string
          decided_at?: string | null
          due_at?: string | null
          flagged_terms?: string[]
          id?: string
          is_priority?: boolean
          payload?: Json
          profile_id?: string
          rejection_reason?: string | null
          status_id?: number
          submitted_at?: string | null
          suggested_therapy?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "profile_revisions_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "public_profile_cards"
            referencedColumns: ["profile_id"]
          },
          {
            foreignKeyName: "profile_revisions_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "public_profile_detail"
            referencedColumns: ["profile_id"]
          },
          {
            foreignKeyName: "profile_revisions_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "therapist_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "profile_revisions_status_id_fkey"
            columns: ["status_id"]
            isOneToOne: false
            referencedRelation: "revision_statuses"
            referencedColumns: ["id"]
          },
        ]
      }
      profile_service_modes: {
        Row: {
          profile_id: string
          service_mode_id: number
        }
        Insert: {
          profile_id: string
          service_mode_id: number
        }
        Update: {
          profile_id?: string
          service_mode_id?: number
        }
        Relationships: [
          {
            foreignKeyName: "profile_service_modes_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "public_profile_cards"
            referencedColumns: ["profile_id"]
          },
          {
            foreignKeyName: "profile_service_modes_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "public_profile_detail"
            referencedColumns: ["profile_id"]
          },
          {
            foreignKeyName: "profile_service_modes_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "therapist_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "profile_service_modes_service_mode_id_fkey"
            columns: ["service_mode_id"]
            isOneToOne: false
            referencedRelation: "service_modes"
            referencedColumns: ["id"]
          },
        ]
      }
      profile_session_formats: {
        Row: {
          profile_id: string
          session_format_id: number
        }
        Insert: {
          profile_id: string
          session_format_id: number
        }
        Update: {
          profile_id?: string
          session_format_id?: number
        }
        Relationships: [
          {
            foreignKeyName: "profile_session_formats_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "public_profile_cards"
            referencedColumns: ["profile_id"]
          },
          {
            foreignKeyName: "profile_session_formats_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "public_profile_detail"
            referencedColumns: ["profile_id"]
          },
          {
            foreignKeyName: "profile_session_formats_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "therapist_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "profile_session_formats_session_format_id_fkey"
            columns: ["session_format_id"]
            isOneToOne: false
            referencedRelation: "session_formats"
            referencedColumns: ["id"]
          },
        ]
      }
      profile_statuses: {
        Row: {
          code: string
          id: number
          is_active: boolean
          sort_order: number
        }
        Insert: {
          code: string
          id?: never
          is_active?: boolean
          sort_order?: number
        }
        Update: {
          code?: string
          id?: never
          is_active?: boolean
          sort_order?: number
        }
        Relationships: []
      }
      profile_therapies: {
        Row: {
          profile_id: string
          session_minutes: number | null
          therapy_id: number
        }
        Insert: {
          profile_id: string
          session_minutes?: number | null
          therapy_id: number
        }
        Update: {
          profile_id?: string
          session_minutes?: number | null
          therapy_id?: number
        }
        Relationships: [
          {
            foreignKeyName: "profile_therapies_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "public_profile_cards"
            referencedColumns: ["profile_id"]
          },
          {
            foreignKeyName: "profile_therapies_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "public_profile_detail"
            referencedColumns: ["profile_id"]
          },
          {
            foreignKeyName: "profile_therapies_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "therapist_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "profile_therapies_therapy_id_fkey"
            columns: ["therapy_id"]
            isOneToOne: false
            referencedRelation: "therapies"
            referencedColumns: ["id"]
          },
        ]
      }
      profile_therapy_rates: {
        Row: {
          amount: number
          currency_id: number
          profile_id: string
          rate_audience_id: number
          therapy_id: number
        }
        Insert: {
          amount: number
          currency_id: number
          profile_id: string
          rate_audience_id: number
          therapy_id: number
        }
        Update: {
          amount?: number
          currency_id?: number
          profile_id?: string
          rate_audience_id?: number
          therapy_id?: number
        }
        Relationships: [
          {
            foreignKeyName: "profile_therapy_rates_currency_id_fkey"
            columns: ["currency_id"]
            isOneToOne: false
            referencedRelation: "currencies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "profile_therapy_rates_profile_id_therapy_id_fkey"
            columns: ["profile_id", "therapy_id"]
            isOneToOne: false
            referencedRelation: "profile_therapies"
            referencedColumns: ["profile_id", "therapy_id"]
          },
          {
            foreignKeyName: "profile_therapy_rates_rate_audience_id_fkey"
            columns: ["rate_audience_id"]
            isOneToOne: false
            referencedRelation: "rate_audiences"
            referencedColumns: ["id"]
          },
        ]
      }
      rate_audiences: {
        Row: {
          code: string
          id: number
          is_active: boolean
          sort_order: number
        }
        Insert: {
          code: string
          id?: never
          is_active?: boolean
          sort_order?: number
        }
        Update: {
          code?: string
          id?: never
          is_active?: boolean
          sort_order?: number
        }
        Relationships: []
      }
      rate_limit_hits: {
        Row: {
          action: string
          day: string
          hits: number
          id: number
          origin_hash: string
        }
        Insert: {
          action: string
          day: string
          hits?: number
          id?: never
          origin_hash: string
        }
        Update: {
          action?: string
          day?: string
          hits?: number
          id?: never
          origin_hash?: string
        }
        Relationships: []
      }
      report_reasons: {
        Row: {
          code: string
          id: number
          is_active: boolean
          sort_order: number
        }
        Insert: {
          code: string
          id?: never
          is_active?: boolean
          sort_order?: number
        }
        Update: {
          code?: string
          id?: never
          is_active?: boolean
          sort_order?: number
        }
        Relationships: []
      }
      report_statuses: {
        Row: {
          code: string
          id: number
          is_active: boolean
          sort_order: number
        }
        Insert: {
          code: string
          id?: never
          is_active?: boolean
          sort_order?: number
        }
        Update: {
          code?: string
          id?: never
          is_active?: boolean
          sort_order?: number
        }
        Relationships: []
      }
      reports: {
        Row: {
          created_at: string
          details: string | null
          id: number
          profile_id: string | null
          reason_id: number
          reporter_email: string | null
          resolution_note: string | null
          resolved_at: string | null
          resolved_by_person_id: string | null
          status_id: number
        }
        Insert: {
          created_at?: string
          details?: string | null
          id?: never
          profile_id?: string | null
          reason_id: number
          reporter_email?: string | null
          resolution_note?: string | null
          resolved_at?: string | null
          resolved_by_person_id?: string | null
          status_id: number
        }
        Update: {
          created_at?: string
          details?: string | null
          id?: never
          profile_id?: string | null
          reason_id?: number
          reporter_email?: string | null
          resolution_note?: string | null
          resolved_at?: string | null
          resolved_by_person_id?: string | null
          status_id?: number
        }
        Relationships: [
          {
            foreignKeyName: "reports_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "public_profile_cards"
            referencedColumns: ["profile_id"]
          },
          {
            foreignKeyName: "reports_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "public_profile_detail"
            referencedColumns: ["profile_id"]
          },
          {
            foreignKeyName: "reports_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "therapist_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "reports_reason_id_fkey"
            columns: ["reason_id"]
            isOneToOne: false
            referencedRelation: "report_reasons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "reports_resolved_by_person_id_fkey"
            columns: ["resolved_by_person_id"]
            isOneToOne: false
            referencedRelation: "people"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "reports_status_id_fkey"
            columns: ["status_id"]
            isOneToOne: false
            referencedRelation: "report_statuses"
            referencedColumns: ["id"]
          },
        ]
      }
      restricted_terms: {
        Row: {
          created_at: string
          id: number
          is_active: boolean
          note: string | null
          term: string
        }
        Insert: {
          created_at?: string
          id?: never
          is_active?: boolean
          note?: string | null
          term: string
        }
        Update: {
          created_at?: string
          id?: never
          is_active?: boolean
          note?: string | null
          term?: string
        }
        Relationships: []
      }
      revision_statuses: {
        Row: {
          code: string
          id: number
          is_active: boolean
          sort_order: number
        }
        Insert: {
          code: string
          id?: never
          is_active?: boolean
          sort_order?: number
        }
        Update: {
          code?: string
          id?: never
          is_active?: boolean
          sort_order?: number
        }
        Relationships: []
      }
      roles: {
        Row: {
          code: string
          id: number
          is_active: boolean
          sort_order: number
        }
        Insert: {
          code: string
          id?: never
          is_active?: boolean
          sort_order?: number
        }
        Update: {
          code?: string
          id?: never
          is_active?: boolean
          sort_order?: number
        }
        Relationships: []
      }
      service_modes: {
        Row: {
          code: string
          id: number
          is_active: boolean
          sort_order: number
        }
        Insert: {
          code: string
          id?: never
          is_active?: boolean
          sort_order?: number
        }
        Update: {
          code?: string
          id?: never
          is_active?: boolean
          sort_order?: number
        }
        Relationships: []
      }
      session_formats: {
        Row: {
          code: string
          id: number
          is_active: boolean
          sort_order: number
        }
        Insert: {
          code: string
          id?: never
          is_active?: boolean
          sort_order?: number
        }
        Update: {
          code?: string
          id?: never
          is_active?: boolean
          sort_order?: number
        }
        Relationships: []
      }
      terms_acceptances: {
        Row: {
          accepted_at: string
          document_type_id: number
          id: string
          person_id: string
          revoked_at: string | null
          version: string
        }
        Insert: {
          accepted_at?: string
          document_type_id: number
          id?: string
          person_id: string
          revoked_at?: string | null
          version: string
        }
        Update: {
          accepted_at?: string
          document_type_id?: number
          id?: string
          person_id?: string
          revoked_at?: string | null
          version?: string
        }
        Relationships: [
          {
            foreignKeyName: "terms_acceptances_document_type_id_fkey"
            columns: ["document_type_id"]
            isOneToOne: false
            referencedRelation: "legal_document_types"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "terms_acceptances_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: false
            referencedRelation: "people"
            referencedColumns: ["id"]
          },
        ]
      }
      therapies: {
        Row: {
          code: string
          created_at: string
          id: number
          is_active: boolean
          sort_order: number
        }
        Insert: {
          code: string
          created_at?: string
          id?: never
          is_active?: boolean
          sort_order?: number
        }
        Update: {
          code?: string
          created_at?: string
          id?: never
          is_active?: boolean
          sort_order?: number
        }
        Relationships: []
      }
      therapist_profiles: {
        Row: {
          approved_at: string | null
          created_at: string
          display_name: string | null
          headline: string | null
          id: string
          is_pinned: boolean
          location_id: number | null
          person_id: string
          photo_path: string | null
          practice_start_year: number | null
          rates_confirmed_at: string | null
          status_id: number
          status_reason: string | null
          zone: string | null
        }
        Insert: {
          approved_at?: string | null
          created_at?: string
          display_name?: string | null
          headline?: string | null
          id?: string
          is_pinned?: boolean
          location_id?: number | null
          person_id: string
          photo_path?: string | null
          practice_start_year?: number | null
          rates_confirmed_at?: string | null
          status_id: number
          status_reason?: string | null
          zone?: string | null
        }
        Update: {
          approved_at?: string | null
          created_at?: string
          display_name?: string | null
          headline?: string | null
          id?: string
          is_pinned?: boolean
          location_id?: number | null
          person_id?: string
          photo_path?: string | null
          practice_start_year?: number | null
          rates_confirmed_at?: string | null
          status_id?: number
          status_reason?: string | null
          zone?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "therapist_profiles_location_id_fkey"
            columns: ["location_id"]
            isOneToOne: false
            referencedRelation: "locations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "therapist_profiles_person_id_fkey"
            columns: ["person_id"]
            isOneToOne: true
            referencedRelation: "people"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "therapist_profiles_status_id_fkey"
            columns: ["status_id"]
            isOneToOne: false
            referencedRelation: "profile_statuses"
            referencedColumns: ["id"]
          },
        ]
      }
      therapy_translations: {
        Row: {
          language_id: number
          name: string
          therapy_id: number
        }
        Insert: {
          language_id: number
          name: string
          therapy_id: number
        }
        Update: {
          language_id?: number
          name?: string
          therapy_id?: number
        }
        Relationships: [
          {
            foreignKeyName: "therapy_translations_language_id_fkey"
            columns: ["language_id"]
            isOneToOne: false
            referencedRelation: "languages"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "therapy_translations_therapy_id_fkey"
            columns: ["therapy_id"]
            isOneToOne: false
            referencedRelation: "therapies"
            referencedColumns: ["id"]
          },
        ]
      }
      unmet_searches: {
        Row: {
          day: string
          id: number
          location_id: number
          searches_count: number
          service_mode_id: number | null
          therapy_id: number
        }
        Insert: {
          day: string
          id?: never
          location_id: number
          searches_count?: number
          service_mode_id?: number | null
          therapy_id: number
        }
        Update: {
          day?: string
          id?: never
          location_id?: number
          searches_count?: number
          service_mode_id?: number | null
          therapy_id?: number
        }
        Relationships: [
          {
            foreignKeyName: "unmet_searches_location_id_fkey"
            columns: ["location_id"]
            isOneToOne: false
            referencedRelation: "locations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "unmet_searches_service_mode_id_fkey"
            columns: ["service_mode_id"]
            isOneToOne: false
            referencedRelation: "service_modes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "unmet_searches_therapy_id_fkey"
            columns: ["therapy_id"]
            isOneToOne: false
            referencedRelation: "therapies"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      public_profile_cards: {
        Row: {
          approved_at: string | null
          city_id: number | null
          city_name: string | null
          country_id: number | null
          country_iso: string | null
          country_name: string | null
          display_name: string | null
          headline: string | null
          is_pinned: boolean | null
          languages: string[] | null
          photo_path: string | null
          profile_id: string | null
          rates_confirmed_at: string | null
          rates_current: boolean | null
          rates_from: Json | null
          region_id: number | null
          region_name: string | null
          service_modes: string[] | null
          session_formats: string[] | null
          therapy_ids: number[] | null
          therapy_names: string[] | null
          zone: string | null
        }
        Relationships: [
          {
            foreignKeyName: "therapist_profiles_location_id_fkey"
            columns: ["city_id"]
            isOneToOne: false
            referencedRelation: "locations"
            referencedColumns: ["id"]
          },
        ]
      }
      public_profile_detail: {
        Row: {
          approved_at: string | null
          city_id: number | null
          city_name: string | null
          country_id: number | null
          country_iso: string | null
          country_name: string | null
          display_name: string | null
          headline: string | null
          is_pinned: boolean | null
          languages: string[] | null
          photo_path: string | null
          practice_start_year: number | null
          profile_id: string | null
          rates_confirmed_at: string | null
          rates_current: boolean | null
          rates_from: Json | null
          region_id: number | null
          region_name: string | null
          service_modes: string[] | null
          session_formats: string[] | null
          therapies_detail: Json | null
          therapy_ids: number[] | null
          therapy_names: string[] | null
          website: string | null
          zone: string | null
        }
        Relationships: [
          {
            foreignKeyName: "therapist_profiles_location_id_fkey"
            columns: ["city_id"]
            isOneToOne: false
            referencedRelation: "locations"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Functions: {
      add_business_days: {
        Args: { p_days: number; p_from: string }
        Returns: string
      }
      apply_revision_payload: {
        Args: { p_payload: Json; p_profile_id: string }
        Returns: undefined
      }
      approve_revision: { Args: { p_revision_id: string }; Returns: undefined }
      check_erasure_fingerprints: {
        Args: { p_fingerprints: Json }
        Returns: number
      }
      close_report: {
        Args: { p_note: string; p_report_id: number; p_status_code: string }
        Returns: undefined
      }
      confirm_my_rates: { Args: never; Returns: undefined }
      current_person_id: { Args: never; Returns: string }
      discard_revision: { Args: { p_revision_id: string }; Returns: undefined }
      erase_therapist: {
        Args: {
          p_fingerprints: Json
          p_person_id: string
          p_requested_by: string
        }
        Returns: {
          auth_user_id: string
          photo_path: string
          profile_id: string
        }[]
      }
      erasure_material: {
        Args: { p_person_id: string }
        Returns: {
          contact_type: string
          value: string
        }[]
      }
      find_restricted_terms: { Args: { p_text: string }; Returns: string[] }
      is_admin: { Args: never; Returns: boolean }
      is_published_profile: { Args: { p_profile: string }; Returns: boolean }
      log_search: {
        Args: {
          p_location_id: number
          p_service_mode?: string
          p_therapy_id: number
        }
        Returns: boolean
      }
      match_restricted_terms: { Args: { p_text: string }; Returns: string[] }
      normalize_text: { Args: { t: string }; Returns: string }
      parse_fingerprints: {
        Args: { p_fingerprints: Json; p_require_nonempty: boolean }
        Returns: {
          contact_type_id: number
          fingerprint: string
        }[]
      }
      public_contact_code: { Args: { p_type: number }; Returns: string }
      purge_expired_audit_log: { Args: never; Returns: number }
      purge_expired_contact_reveals: { Args: never; Returns: number }
      purge_expired_erasure_fingerprints: { Args: never; Returns: number }
      purge_expired_rate_limit_hits: { Args: never; Returns: number }
      purge_expired_reports: { Args: never; Returns: number }
      purge_expired_unmet_searches: { Args: never; Returns: number }
      rates_validity_months: { Args: never; Returns: number }
      register_therapist: {
        Args: { p_acceptances: Json; p_full_name: string }
        Returns: string
      }
      reinstate_profile: {
        Args: { p_profile_id: string; p_reason: string }
        Returns: undefined
      }
      reject_revision: {
        Args: { p_reason: string; p_revision_id: string }
        Returns: undefined
      }
      report_profile: {
        Args: {
          p_details?: string
          p_profile_id: string
          p_reason_code: string
          p_reporter_email?: string
        }
        Returns: number
      }
      reveal_contact: {
        Args: { p_profile_id: string }
        Returns: {
          accepts_whatsapp: boolean
          contact_type: string
          value: string
        }[]
      }
      reveal_contact_limited: {
        Args: { p_origin_hash: string; p_profile_id: string }
        Returns: {
          accepts_whatsapp: boolean
          contact_type: string
          value: string
        }[]
      }
      revision_int: { Args: { label: string; v: Json }; Returns: number }
      search_profiles: {
        Args: {
          p_limit?: number
          p_location_id: number
          p_offset?: number
          p_service_mode?: string
          p_therapy_id: number
        }
        Returns: {
          approved_at: string
          city_id: number
          city_name: string
          country_id: number
          country_iso: string
          country_name: string
          display_name: string
          headline: string
          is_pinned: boolean
          languages: string[]
          photo_path: string
          profile_id: string
          rates_confirmed_at: string
          rates_current: boolean
          rates_from: Json
          region_id: number
          region_name: string
          result_group: number
          service_modes: string[]
          session_formats: string[]
          therapy_ids: number[]
          therapy_names: string[]
          total_count: number
          zone: string
        }[]
      }
      set_offers_consent: {
        Args: { p_value: boolean; p_version?: string }
        Returns: undefined
      }
      set_profile_pinned: {
        Args: { p_pinned: boolean; p_profile_id: string }
        Returns: undefined
      }
      submit_revision: { Args: { p_revision_id: string }; Returns: string[] }
      suspend_profile: {
        Args: { p_profile_id: string; p_reason: string }
        Returns: undefined
      }
      update_my_rates: { Args: { p_rates: Json }; Returns: undefined }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends (DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never) = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends (PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never) = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {},
  },
} as const
