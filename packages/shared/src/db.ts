/* مولَّد آليًا من مخطط قاعدة البيانات — لا تحرّره يدويًا.
 * أعد التوليد بـ: pnpm gen:types
 */

export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  public: {
    Tables: {
      app_settings: {
        Row: {
          description: string | null
          key: string
          updated_at: string
          value: Json
        }
        Insert: {
          description?: string | null
          key: string
          updated_at?: string
          value: Json
        }
        Update: {
          description?: string | null
          key?: string
          updated_at?: string
          value?: Json
        }
        Relationships: []
      }
      cash_collections: {
        Row: {
          amount: number
          business_date: string
          collected_at: string
          courier_id: string
          id: string
          order_id: string
          reverse_reason: string | null
          reversed_at: string | null
          reversed_by: string | null
          settlement_id: string | null
        }
        Insert: {
          amount: number
          business_date: string
          collected_at?: string
          courier_id: string
          id?: string
          order_id: string
          reverse_reason?: string | null
          reversed_at?: string | null
          reversed_by?: string | null
          settlement_id?: string | null
        }
        Update: {
          amount?: number
          business_date?: string
          collected_at?: string
          courier_id?: string
          id?: string
          order_id?: string
          reverse_reason?: string | null
          reversed_at?: string | null
          reversed_by?: string | null
          settlement_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "cash_collections_courier_id_fkey"
            columns: ["courier_id"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "cash_collections_courier_id_fkey"
            columns: ["courier_id"]
            isOneToOne: false
            referencedRelation: "v_courier_performance"
            referencedColumns: ["courier_id"]
          },
          {
            foreignKeyName: "cash_collections_order_id_fkey"
            columns: ["order_id"]
            isOneToOne: true
            referencedRelation: "orders"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "cash_collections_order_id_fkey"
            columns: ["order_id"]
            isOneToOne: true
            referencedRelation: "v_stale_orders"
            referencedColumns: ["order_id"]
          },
          {
            foreignKeyName: "cash_collections_order_id_fkey"
            columns: ["order_id"]
            isOneToOne: true
            referencedRelation: "v_unpaid_aging"
            referencedColumns: ["order_id"]
          },
          {
            foreignKeyName: "cash_collections_reversed_by_fkey"
            columns: ["reversed_by"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "cash_collections_reversed_by_fkey"
            columns: ["reversed_by"]
            isOneToOne: false
            referencedRelation: "v_courier_performance"
            referencedColumns: ["courier_id"]
          },
          {
            foreignKeyName: "cash_collections_settlement_id_fkey"
            columns: ["settlement_id"]
            isOneToOne: false
            referencedRelation: "cash_settlements"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "cash_collections_settlement_id_fkey"
            columns: ["settlement_id"]
            isOneToOne: false
            referencedRelation: "v_awaiting_verification"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "cash_collections_settlement_id_fkey"
            columns: ["settlement_id"]
            isOneToOne: false
            referencedRelation: "v_handover_exceptions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "cash_collections_settlement_id_fkey"
            columns: ["settlement_id"]
            isOneToOne: false
            referencedRelation: "v_unmatched_deposits"
            referencedColumns: ["id"]
          },
        ]
      }
      cash_settlements: {
        Row: {
          approved_at: string | null
          approved_by: string | null
          bank_matched_at: string | null
          bank_matched_by: string | null
          bank_reference: string | null
          business_date: string
          confirmed_amount: number | null
          courier_id: string
          created_at: string
          declared_amount: number | null
          expected_amount: number
          handover_at: string | null
          handover_exception_reason: string | null
          handover_method: Database["public"]["Enums"]["handover_method"] | null
          handover_note: string | null
          handover_photo_id: string | null
          handover_reference: string | null
          id: string
          notes: string | null
          opened_at: string
          state: Database["public"]["Enums"]["settlement_state"]
          updated_at: string
          variance: number | null
          variance_reason: string | null
          verified_at: string | null
          verified_by: string | null
        }
        Insert: {
          approved_at?: string | null
          approved_by?: string | null
          bank_matched_at?: string | null
          bank_matched_by?: string | null
          bank_reference?: string | null
          business_date: string
          confirmed_amount?: number | null
          courier_id: string
          created_at?: string
          declared_amount?: number | null
          expected_amount?: number
          handover_at?: string | null
          handover_exception_reason?: string | null
          handover_method?:
            | Database["public"]["Enums"]["handover_method"]
            | null
          handover_note?: string | null
          handover_photo_id?: string | null
          handover_reference?: string | null
          id?: string
          notes?: string | null
          opened_at?: string
          state?: Database["public"]["Enums"]["settlement_state"]
          updated_at?: string
          variance?: number | null
          variance_reason?: string | null
          verified_at?: string | null
          verified_by?: string | null
        }
        Update: {
          approved_at?: string | null
          approved_by?: string | null
          bank_matched_at?: string | null
          bank_matched_by?: string | null
          bank_reference?: string | null
          business_date?: string
          confirmed_amount?: number | null
          courier_id?: string
          created_at?: string
          declared_amount?: number | null
          expected_amount?: number
          handover_at?: string | null
          handover_exception_reason?: string | null
          handover_method?:
            | Database["public"]["Enums"]["handover_method"]
            | null
          handover_note?: string | null
          handover_photo_id?: string | null
          handover_reference?: string | null
          id?: string
          notes?: string | null
          opened_at?: string
          state?: Database["public"]["Enums"]["settlement_state"]
          updated_at?: string
          variance?: number | null
          variance_reason?: string | null
          verified_at?: string | null
          verified_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "cash_settlements_approved_by_fkey"
            columns: ["approved_by"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "cash_settlements_approved_by_fkey"
            columns: ["approved_by"]
            isOneToOne: false
            referencedRelation: "v_courier_performance"
            referencedColumns: ["courier_id"]
          },
          {
            foreignKeyName: "cash_settlements_bank_matched_by_fkey"
            columns: ["bank_matched_by"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "cash_settlements_bank_matched_by_fkey"
            columns: ["bank_matched_by"]
            isOneToOne: false
            referencedRelation: "v_courier_performance"
            referencedColumns: ["courier_id"]
          },
          {
            foreignKeyName: "cash_settlements_courier_id_fkey"
            columns: ["courier_id"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "cash_settlements_courier_id_fkey"
            columns: ["courier_id"]
            isOneToOne: false
            referencedRelation: "v_courier_performance"
            referencedColumns: ["courier_id"]
          },
          {
            foreignKeyName: "cash_settlements_handover_photo_id_fkey"
            columns: ["handover_photo_id"]
            isOneToOne: false
            referencedRelation: "order_photos"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "cash_settlements_verified_by_fkey"
            columns: ["verified_by"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "cash_settlements_verified_by_fkey"
            columns: ["verified_by"]
            isOneToOne: false
            referencedRelation: "v_courier_performance"
            referencedColumns: ["courier_id"]
          },
        ]
      }
      customer_qr_tokens: {
        Row: {
          customer_id: string
          id: string
          issued_at: string
          issued_by: string | null
          revoke_reason: string | null
          revoked_at: string | null
          revoked_by: string | null
          token: string
        }
        Insert: {
          customer_id: string
          id?: string
          issued_at?: string
          issued_by?: string | null
          revoke_reason?: string | null
          revoked_at?: string | null
          revoked_by?: string | null
          token?: string
        }
        Update: {
          customer_id?: string
          id?: string
          issued_at?: string
          issued_by?: string | null
          revoke_reason?: string | null
          revoked_at?: string | null
          revoked_by?: string | null
          token?: string
        }
        Relationships: [
          {
            foreignKeyName: "customer_qr_tokens_customer_id_fkey"
            columns: ["customer_id"]
            isOneToOne: false
            referencedRelation: "customers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "customer_qr_tokens_issued_by_fkey"
            columns: ["issued_by"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "customer_qr_tokens_issued_by_fkey"
            columns: ["issued_by"]
            isOneToOne: false
            referencedRelation: "v_courier_performance"
            referencedColumns: ["courier_id"]
          },
          {
            foreignKeyName: "customer_qr_tokens_revoked_by_fkey"
            columns: ["revoked_by"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "customer_qr_tokens_revoked_by_fkey"
            columns: ["revoked_by"]
            isOneToOne: false
            referencedRelation: "v_courier_performance"
            referencedColumns: ["courier_id"]
          },
        ]
      }
      customers: {
        Row: {
          apartment_number: string | null
          created_at: string
          created_by: string | null
          customer_no: number
          deleted_at: string | null
          floor_number: string | null
          full_name: string | null
          id: string
          is_active: boolean
          notes: string | null
          phone: string | null
          profile_completed_at: string | null
          profile_status: Database["public"]["Enums"]["profile_status"]
          property_id: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          apartment_number?: string | null
          created_at?: string
          created_by?: string | null
          customer_no?: never
          deleted_at?: string | null
          floor_number?: string | null
          full_name?: string | null
          id?: string
          is_active?: boolean
          notes?: string | null
          phone?: string | null
          profile_completed_at?: string | null
          profile_status?: Database["public"]["Enums"]["profile_status"]
          property_id: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          apartment_number?: string | null
          created_at?: string
          created_by?: string | null
          customer_no?: never
          deleted_at?: string | null
          floor_number?: string | null
          full_name?: string | null
          id?: string
          is_active?: boolean
          notes?: string | null
          phone?: string | null
          profile_completed_at?: string | null
          profile_status?: Database["public"]["Enums"]["profile_status"]
          property_id?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "customers_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "customers_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "v_courier_performance"
            referencedColumns: ["courier_id"]
          },
          {
            foreignKeyName: "customers_property_id_fkey"
            columns: ["property_id"]
            isOneToOne: false
            referencedRelation: "properties"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "customers_property_id_fkey"
            columns: ["property_id"]
            isOneToOne: false
            referencedRelation: "v_orders_by_property"
            referencedColumns: ["property_id"]
          },
          {
            foreignKeyName: "customers_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "customers_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "v_courier_performance"
            referencedColumns: ["courier_id"]
          },
        ]
      }
      order_photos: {
        Row: {
          byte_size: number
          id: string
          kind: Database["public"]["Enums"]["photo_kind"]
          latitude: number | null
          longitude: number | null
          order_id: string | null
          sha256: string
          storage_path: string
          taken_at: string
          taken_by: string | null
        }
        Insert: {
          byte_size: number
          id?: string
          kind: Database["public"]["Enums"]["photo_kind"]
          latitude?: number | null
          longitude?: number | null
          order_id?: string | null
          sha256: string
          storage_path: string
          taken_at?: string
          taken_by?: string | null
        }
        Update: {
          byte_size?: number
          id?: string
          kind?: Database["public"]["Enums"]["photo_kind"]
          latitude?: number | null
          longitude?: number | null
          order_id?: string | null
          sha256?: string
          storage_path?: string
          taken_at?: string
          taken_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "order_photos_order_id_fkey"
            columns: ["order_id"]
            isOneToOne: false
            referencedRelation: "orders"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "order_photos_order_id_fkey"
            columns: ["order_id"]
            isOneToOne: false
            referencedRelation: "v_stale_orders"
            referencedColumns: ["order_id"]
          },
          {
            foreignKeyName: "order_photos_order_id_fkey"
            columns: ["order_id"]
            isOneToOne: false
            referencedRelation: "v_unpaid_aging"
            referencedColumns: ["order_id"]
          },
          {
            foreignKeyName: "order_photos_taken_by_fkey"
            columns: ["taken_by"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "order_photos_taken_by_fkey"
            columns: ["taken_by"]
            isOneToOne: false
            referencedRelation: "v_courier_performance"
            referencedColumns: ["courier_id"]
          },
        ]
      }
      order_status_history: {
        Row: {
          changed_at: string
          changed_by: string | null
          context: Json
          from_status: Database["public"]["Enums"]["order_status"] | null
          id: number
          order_id: string
          reason: string | null
          request_id: string | null
          to_status: Database["public"]["Enums"]["order_status"]
        }
        Insert: {
          changed_at?: string
          changed_by?: string | null
          context?: Json
          from_status?: Database["public"]["Enums"]["order_status"] | null
          id?: never
          order_id: string
          reason?: string | null
          request_id?: string | null
          to_status: Database["public"]["Enums"]["order_status"]
        }
        Update: {
          changed_at?: string
          changed_by?: string | null
          context?: Json
          from_status?: Database["public"]["Enums"]["order_status"] | null
          id?: never
          order_id?: string
          reason?: string | null
          request_id?: string | null
          to_status?: Database["public"]["Enums"]["order_status"]
        }
        Relationships: [
          {
            foreignKeyName: "order_status_history_changed_by_fkey"
            columns: ["changed_by"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "order_status_history_changed_by_fkey"
            columns: ["changed_by"]
            isOneToOne: false
            referencedRelation: "v_courier_performance"
            referencedColumns: ["courier_id"]
          },
          {
            foreignKeyName: "order_status_history_order_id_fkey"
            columns: ["order_id"]
            isOneToOne: false
            referencedRelation: "orders"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "order_status_history_order_id_fkey"
            columns: ["order_id"]
            isOneToOne: false
            referencedRelation: "v_stale_orders"
            referencedColumns: ["order_id"]
          },
          {
            foreignKeyName: "order_status_history_order_id_fkey"
            columns: ["order_id"]
            isOneToOne: false
            referencedRelation: "v_unpaid_aging"
            referencedColumns: ["order_id"]
          },
        ]
      }
      order_status_settings: {
        Row: {
          label_ar: string
          notification_message: string
          notify_enabled: boolean
          sort_order: number
          status: Database["public"]["Enums"]["order_status"]
          template_name: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          label_ar: string
          notification_message: string
          notify_enabled?: boolean
          sort_order: number
          status: Database["public"]["Enums"]["order_status"]
          template_name?: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          label_ar?: string
          notification_message?: string
          notify_enabled?: boolean
          sort_order?: number
          status?: Database["public"]["Enums"]["order_status"]
          template_name?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "order_status_settings_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "order_status_settings_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "v_courier_performance"
            referencedColumns: ["courier_id"]
          },
        ]
      }
      order_submissions: {
        Row: {
          consumed_at: string | null
          created_at: string
          customer_id: string
          expires_at: string
          id: string
          order_id: string | null
          otp_challenge_id: string
          token_hash: string
        }
        Insert: {
          consumed_at?: string | null
          created_at?: string
          customer_id: string
          expires_at: string
          id?: string
          order_id?: string | null
          otp_challenge_id: string
          token_hash: string
        }
        Update: {
          consumed_at?: string | null
          created_at?: string
          customer_id?: string
          expires_at?: string
          id?: string
          order_id?: string | null
          otp_challenge_id?: string
          token_hash?: string
        }
        Relationships: [
          {
            foreignKeyName: "order_submissions_customer_id_fkey"
            columns: ["customer_id"]
            isOneToOne: false
            referencedRelation: "customers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "order_submissions_otp_challenge_id_fkey"
            columns: ["otp_challenge_id"]
            isOneToOne: true
            referencedRelation: "otp_challenges"
            referencedColumns: ["id"]
          },
        ]
      }
      orders: {
        Row: {
          cancel_reason: string | null
          cancelled_at: string | null
          cancelled_by: string | null
          created_at: string
          customer_id: string
          delivery_confirmed_at: string | null
          delivery_confirmed_by: string | null
          id: string
          invoice_amount: number | null
          invoice_number: string | null
          invoiced_at: string | null
          invoiced_by: string | null
          order_no: number
          paid_at: string | null
          paid_recorded_by: string | null
          payment_method: Database["public"]["Enums"]["payment_method"] | null
          payment_status: Database["public"]["Enums"]["payment_status"]
          pickup_confirmed_at: string | null
          pickup_confirmed_by: string | null
          property_id: string
          scan_event_id: string | null
          status: Database["public"]["Enums"]["order_status"]
          status_changed_at: string
          submission_id: string | null
          updated_at: string
        }
        Insert: {
          cancel_reason?: string | null
          cancelled_at?: string | null
          cancelled_by?: string | null
          created_at?: string
          customer_id: string
          delivery_confirmed_at?: string | null
          delivery_confirmed_by?: string | null
          id?: string
          invoice_amount?: number | null
          invoice_number?: string | null
          invoiced_at?: string | null
          invoiced_by?: string | null
          order_no?: never
          paid_at?: string | null
          paid_recorded_by?: string | null
          payment_method?: Database["public"]["Enums"]["payment_method"] | null
          payment_status?: Database["public"]["Enums"]["payment_status"]
          pickup_confirmed_at?: string | null
          pickup_confirmed_by?: string | null
          property_id: string
          scan_event_id?: string | null
          status?: Database["public"]["Enums"]["order_status"]
          status_changed_at?: string
          submission_id?: string | null
          updated_at?: string
        }
        Update: {
          cancel_reason?: string | null
          cancelled_at?: string | null
          cancelled_by?: string | null
          created_at?: string
          customer_id?: string
          delivery_confirmed_at?: string | null
          delivery_confirmed_by?: string | null
          id?: string
          invoice_amount?: number | null
          invoice_number?: string | null
          invoiced_at?: string | null
          invoiced_by?: string | null
          order_no?: never
          paid_at?: string | null
          paid_recorded_by?: string | null
          payment_method?: Database["public"]["Enums"]["payment_method"] | null
          payment_status?: Database["public"]["Enums"]["payment_status"]
          pickup_confirmed_at?: string | null
          pickup_confirmed_by?: string | null
          property_id?: string
          scan_event_id?: string | null
          status?: Database["public"]["Enums"]["order_status"]
          status_changed_at?: string
          submission_id?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "orders_cancelled_by_fkey"
            columns: ["cancelled_by"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "orders_cancelled_by_fkey"
            columns: ["cancelled_by"]
            isOneToOne: false
            referencedRelation: "v_courier_performance"
            referencedColumns: ["courier_id"]
          },
          {
            foreignKeyName: "orders_customer_id_fkey"
            columns: ["customer_id"]
            isOneToOne: false
            referencedRelation: "customers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "orders_delivery_confirmed_by_fkey"
            columns: ["delivery_confirmed_by"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "orders_delivery_confirmed_by_fkey"
            columns: ["delivery_confirmed_by"]
            isOneToOne: false
            referencedRelation: "v_courier_performance"
            referencedColumns: ["courier_id"]
          },
          {
            foreignKeyName: "orders_invoiced_by_fkey"
            columns: ["invoiced_by"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "orders_invoiced_by_fkey"
            columns: ["invoiced_by"]
            isOneToOne: false
            referencedRelation: "v_courier_performance"
            referencedColumns: ["courier_id"]
          },
          {
            foreignKeyName: "orders_paid_recorded_by_fkey"
            columns: ["paid_recorded_by"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "orders_paid_recorded_by_fkey"
            columns: ["paid_recorded_by"]
            isOneToOne: false
            referencedRelation: "v_courier_performance"
            referencedColumns: ["courier_id"]
          },
          {
            foreignKeyName: "orders_pickup_confirmed_by_fkey"
            columns: ["pickup_confirmed_by"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "orders_pickup_confirmed_by_fkey"
            columns: ["pickup_confirmed_by"]
            isOneToOne: false
            referencedRelation: "v_courier_performance"
            referencedColumns: ["courier_id"]
          },
          {
            foreignKeyName: "orders_property_id_fkey"
            columns: ["property_id"]
            isOneToOne: false
            referencedRelation: "properties"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "orders_property_id_fkey"
            columns: ["property_id"]
            isOneToOne: false
            referencedRelation: "v_orders_by_property"
            referencedColumns: ["property_id"]
          },
          {
            foreignKeyName: "orders_scan_event_id_fkey"
            columns: ["scan_event_id"]
            isOneToOne: true
            referencedRelation: "scan_events"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "orders_submission_id_fkey"
            columns: ["submission_id"]
            isOneToOne: true
            referencedRelation: "order_submissions"
            referencedColumns: ["id"]
          },
        ]
      }
      otp_challenges: {
        Row: {
          attempts: number
          code_hash: string
          created_at: string
          customer_id: string
          expires_at: string
          id: string
          max_attempts: number
          phone_snapshot: string
          scan_event_id: string
          state: Database["public"]["Enums"]["otp_state"]
          verified_at: string | null
        }
        Insert: {
          attempts?: number
          code_hash: string
          created_at?: string
          customer_id: string
          expires_at: string
          id?: string
          max_attempts?: number
          phone_snapshot: string
          scan_event_id: string
          state?: Database["public"]["Enums"]["otp_state"]
          verified_at?: string | null
        }
        Update: {
          attempts?: number
          code_hash?: string
          created_at?: string
          customer_id?: string
          expires_at?: string
          id?: string
          max_attempts?: number
          phone_snapshot?: string
          scan_event_id?: string
          state?: Database["public"]["Enums"]["otp_state"]
          verified_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "otp_challenges_customer_id_fkey"
            columns: ["customer_id"]
            isOneToOne: false
            referencedRelation: "customers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "otp_challenges_scan_event_id_fkey"
            columns: ["scan_event_id"]
            isOneToOne: false
            referencedRelation: "scan_events"
            referencedColumns: ["id"]
          },
        ]
      }
      payment_events: {
        Row: {
          created_at: string
          created_by: string | null
          event_type: string
          id: number
          new_status: string | null
          old_status: string | null
          order_id: string
          payment_id: string | null
          provider_ref: string | null
          safe_payload: Json
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          event_type: string
          id?: never
          new_status?: string | null
          old_status?: string | null
          order_id: string
          payment_id?: string | null
          provider_ref?: string | null
          safe_payload?: Json
        }
        Update: {
          created_at?: string
          created_by?: string | null
          event_type?: string
          id?: never
          new_status?: string | null
          old_status?: string | null
          order_id?: string
          payment_id?: string | null
          provider_ref?: string | null
          safe_payload?: Json
        }
        Relationships: [
          {
            foreignKeyName: "payment_events_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "payment_events_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "v_courier_performance"
            referencedColumns: ["courier_id"]
          },
          {
            foreignKeyName: "payment_events_order_id_fkey"
            columns: ["order_id"]
            isOneToOne: false
            referencedRelation: "orders"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "payment_events_order_id_fkey"
            columns: ["order_id"]
            isOneToOne: false
            referencedRelation: "v_stale_orders"
            referencedColumns: ["order_id"]
          },
          {
            foreignKeyName: "payment_events_order_id_fkey"
            columns: ["order_id"]
            isOneToOne: false
            referencedRelation: "v_unpaid_aging"
            referencedColumns: ["order_id"]
          },
          {
            foreignKeyName: "payment_events_payment_id_fkey"
            columns: ["payment_id"]
            isOneToOne: false
            referencedRelation: "payments"
            referencedColumns: ["id"]
          },
        ]
      }
      payments: {
        Row: {
          amount_baisa: number
          checkout_url: string | null
          created_at: string
          created_by: string | null
          currency: string
          id: string
          idempotency_key: string
          order_id: string
          provider: string
          provider_session_id: string | null
          return_token_hash: string | null
          status: string
          updated_at: string
        }
        Insert: {
          amount_baisa: number
          checkout_url?: string | null
          created_at?: string
          created_by?: string | null
          currency?: string
          id?: string
          idempotency_key: string
          order_id: string
          provider?: string
          provider_session_id?: string | null
          return_token_hash?: string | null
          status?: string
          updated_at?: string
        }
        Update: {
          amount_baisa?: number
          checkout_url?: string | null
          created_at?: string
          created_by?: string | null
          currency?: string
          id?: string
          idempotency_key?: string
          order_id?: string
          provider?: string
          provider_session_id?: string | null
          return_token_hash?: string | null
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "payments_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "payments_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "v_courier_performance"
            referencedColumns: ["courier_id"]
          },
          {
            foreignKeyName: "payments_order_id_fkey"
            columns: ["order_id"]
            isOneToOne: false
            referencedRelation: "orders"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "payments_order_id_fkey"
            columns: ["order_id"]
            isOneToOne: false
            referencedRelation: "v_stale_orders"
            referencedColumns: ["order_id"]
          },
          {
            foreignKeyName: "payments_order_id_fkey"
            columns: ["order_id"]
            isOneToOne: false
            referencedRelation: "v_unpaid_aging"
            referencedColumns: ["order_id"]
          },
        ]
      }
      properties: {
        Row: {
          address: string | null
          code: string
          created_at: string
          created_by: string | null
          deleted_at: string | null
          id: string
          is_active: boolean
          latitude: number | null
          longitude: number | null
          name: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          address?: string | null
          code: string
          created_at?: string
          created_by?: string | null
          deleted_at?: string | null
          id?: string
          is_active?: boolean
          latitude?: number | null
          longitude?: number | null
          name: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          address?: string | null
          code?: string
          created_at?: string
          created_by?: string | null
          deleted_at?: string | null
          id?: string
          is_active?: boolean
          latitude?: number | null
          longitude?: number | null
          name?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "properties_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "properties_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "v_courier_performance"
            referencedColumns: ["courier_id"]
          },
          {
            foreignKeyName: "properties_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "properties_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "v_courier_performance"
            referencedColumns: ["courier_id"]
          },
        ]
      }
      public_holidays: {
        Row: {
          created_at: string
          created_by: string | null
          holiday_date: string
          label: string
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          holiday_date: string
          label: string
        }
        Update: {
          created_at?: string
          created_by?: string | null
          holiday_date?: string
          label?: string
        }
        Relationships: [
          {
            foreignKeyName: "public_holidays_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "public_holidays_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "v_courier_performance"
            referencedColumns: ["courier_id"]
          },
        ]
      }
      scan_events: {
        Row: {
          customer_id: string | null
          id: string
          ip_hash: string | null
          order_submitted_at: string | null
          otp_requested_at: string | null
          qr_token_id: string | null
          request_id: string | null
          result: string
          scan_session_id: string
          scanned_at: string
          user_agent: string | null
          verified_at: string | null
        }
        Insert: {
          customer_id?: string | null
          id?: string
          ip_hash?: string | null
          order_submitted_at?: string | null
          otp_requested_at?: string | null
          qr_token_id?: string | null
          request_id?: string | null
          result: string
          scan_session_id?: string
          scanned_at?: string
          user_agent?: string | null
          verified_at?: string | null
        }
        Update: {
          customer_id?: string | null
          id?: string
          ip_hash?: string | null
          order_submitted_at?: string | null
          otp_requested_at?: string | null
          qr_token_id?: string | null
          request_id?: string | null
          result?: string
          scan_session_id?: string
          scanned_at?: string
          user_agent?: string | null
          verified_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "scan_events_customer_id_fkey"
            columns: ["customer_id"]
            isOneToOne: false
            referencedRelation: "customers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "scan_events_qr_token_id_fkey"
            columns: ["qr_token_id"]
            isOneToOne: false
            referencedRelation: "customer_qr_tokens"
            referencedColumns: ["id"]
          },
        ]
      }
      staff: {
        Row: {
          created_at: string
          created_by: string | null
          deleted_at: string | null
          full_name: string
          id: string
          is_active: boolean
          phone: string | null
          role: Database["public"]["Enums"]["staff_role"]
          updated_at: string
          user_id: string
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          deleted_at?: string | null
          full_name: string
          id?: string
          is_active?: boolean
          phone?: string | null
          role?: Database["public"]["Enums"]["staff_role"]
          updated_at?: string
          user_id: string
        }
        Update: {
          created_at?: string
          created_by?: string | null
          deleted_at?: string | null
          full_name?: string
          id?: string
          is_active?: boolean
          phone?: string | null
          role?: Database["public"]["Enums"]["staff_role"]
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "staff_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "staff_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "v_courier_performance"
            referencedColumns: ["courier_id"]
          },
        ]
      }
    }
    Views: {
      mv_stage_durations: {
        Row: {
          avg_hours: number | null
          latest_sample: string | null
          median_hours: number | null
          p95_hours: number | null
          sample_size: number | null
          stage: Database["public"]["Enums"]["order_status"] | null
        }
        Relationships: []
      }
      v_awaiting_verification: {
        Row: {
          business_date: string | null
          courier_id: string | null
          courier_name: string | null
          declared_amount: number | null
          expected_amount: number | null
          handover_at: string | null
          handover_method: Database["public"]["Enums"]["handover_method"] | null
          handover_photo_id: string | null
          handover_reference: string | null
          hours_since_handover: number | null
          id: string | null
          sla_breached: boolean | null
          state: Database["public"]["Enums"]["settlement_state"] | null
        }
        Relationships: [
          {
            foreignKeyName: "cash_settlements_courier_id_fkey"
            columns: ["courier_id"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "cash_settlements_courier_id_fkey"
            columns: ["courier_id"]
            isOneToOne: false
            referencedRelation: "v_courier_performance"
            referencedColumns: ["courier_id"]
          },
          {
            foreignKeyName: "cash_settlements_handover_photo_id_fkey"
            columns: ["handover_photo_id"]
            isOneToOne: false
            referencedRelation: "order_photos"
            referencedColumns: ["id"]
          },
        ]
      }
      v_courier_performance: {
        Row: {
          cash_collected: number | null
          courier_id: string | null
          courier_name: string | null
          deliveries: number | null
          pickups: number | null
        }
        Relationships: []
      }
      v_courier_variance_history: {
        Row: {
          average_handover_gap_hours: number | null
          average_variance: number | null
          courier_id: string | null
          courier_name: string | null
          total_variance: number | null
          variance_count: number | null
          verified_count: number | null
        }
        Relationships: [
          {
            foreignKeyName: "cash_settlements_courier_id_fkey"
            columns: ["courier_id"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "cash_settlements_courier_id_fkey"
            columns: ["courier_id"]
            isOneToOne: false
            referencedRelation: "v_courier_performance"
            referencedColumns: ["courier_id"]
          },
        ]
      }
      v_daily_cash_reconciliation: {
        Row: {
          business_date: string | null
          collections_count: number | null
          collections_total: number | null
          reversed_count: number | null
        }
        Relationships: []
      }
      v_dashboard_kpis: {
        Row: {
          customers_complete: number | null
          customers_incomplete: number | null
          customers_total: number | null
          orders_active: number | null
          orders_today: number | null
          orders_total: number | null
          properties_active: number | null
          revenue_collected: number | null
          revenue_pending: number | null
        }
        Relationships: []
      }
      v_handover_exceptions: {
        Row: {
          business_date: string | null
          confirmed_amount: number | null
          courier_name: string | null
          handover_exception_reason: string | null
          handover_method: Database["public"]["Enums"]["handover_method"] | null
          id: string | null
          state: Database["public"]["Enums"]["settlement_state"] | null
        }
        Relationships: []
      }
      v_orders_by_property: {
        Row: {
          code: string | null
          name: string | null
          orders_active: number | null
          orders_cancelled: number | null
          orders_completed: number | null
          orders_total: number | null
          property_id: string | null
          revenue: number | null
        }
        Relationships: []
      }
      v_orders_by_status: {
        Row: {
          orders_count: number | null
          status: Database["public"]["Enums"]["order_status"] | null
        }
        Relationships: []
      }
      v_pending_cash: {
        Row: {
          blocked: boolean | null
          courier_id: string | null
          courier_name: string | null
          oldest_business_date: string | null
          open_settlements: number | null
          unhanded_amount: number | null
          working_days_unhanded: number | null
        }
        Relationships: [
          {
            foreignKeyName: "cash_settlements_courier_id_fkey"
            columns: ["courier_id"]
            isOneToOne: false
            referencedRelation: "staff"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "cash_settlements_courier_id_fkey"
            columns: ["courier_id"]
            isOneToOne: false
            referencedRelation: "v_courier_performance"
            referencedColumns: ["courier_id"]
          },
        ]
      }
      v_revenue_by_method: {
        Row: {
          business_date: string | null
          orders_count: number | null
          payment_method: Database["public"]["Enums"]["payment_method"] | null
          total: number | null
        }
        Relationships: []
      }
      v_scan_funnel: {
        Row: {
          business_date: string | null
          conversion_pct: number | null
          orders_submitted: number | null
          otp_requested: number | null
          rejected: number | null
          scans_total: number | null
          verified: number | null
        }
        Relationships: []
      }
      v_stale_orders: {
        Row: {
          customer_name: string | null
          hours_in_status: number | null
          order_id: string | null
          order_no: number | null
          property_name: string | null
          status: Database["public"]["Enums"]["order_status"] | null
          status_changed_at: string | null
        }
        Relationships: []
      }
      v_unmatched_deposits: {
        Row: {
          business_date: string | null
          confirmed_amount: number | null
          courier_name: string | null
          days_unmatched: number | null
          handover_reference: string | null
          id: string | null
          sla_breached: boolean | null
          verified_at: string | null
        }
        Relationships: []
      }
      v_unpaid_aging: {
        Row: {
          age_bucket: string | null
          days_outstanding: number | null
          invoice_amount: number | null
          invoice_number: string | null
          invoiced_at: string | null
          order_id: string | null
          order_no: number | null
          property_name: string | null
        }
        Relationships: []
      }
    }
    Functions: {
      auth_role: {
        Args: never
        Returns: Database["public"]["Enums"]["staff_role"]
      }
      auth_role_at_least: {
        Args: { minimum: Database["public"]["Enums"]["staff_role"] }
        Returns: boolean
      }
      auth_staff_id: { Args: never; Returns: string }
      business_date_of: { Args: { ts?: string }; Returns: string }
      fn_advance_status: {
        Args: {
          p_expected_status: Database["public"]["Enums"]["order_status"]
          p_order_id: string
          p_to_status: Database["public"]["Enums"]["order_status"]
        }
        Returns: Json
      }
      fn_apply_payment_webhook: {
        Args: {
          p_provider_status: string
          p_safe_payload?: Json
          p_session_id: string
        }
        Returns: Json
      }
      fn_apply_retention: { Args: never; Returns: Json }
      fn_approve_variance: {
        Args: { p_reason: string; p_settlement_id: string }
        Returns: Json
      }
      fn_attach_checkout: {
        Args: {
          p_amount: number
          p_checkout_url: string
          p_invoice_number: string
          p_payment_id: string
          p_return_token_hash: string
          p_session_id: string
        }
        Returns: Json
      }
      fn_cancel_order: {
        Args: { p_order_id: string; p_reason: string }
        Returns: Json
      }
      fn_claim_outbox_batch: {
        Args: { p_limit?: number }
        Returns: {
          attempts: number
          id: number
          idempotency_key: string
          params: Json
          recipient: string
          template_name: string
        }[]
      }
      fn_complete_profile: {
        Args: {
          p_apartment_number: string
          p_floor_number: string
          p_full_name: string
          p_phone: string
          p_scan_session: string
        }
        Returns: Json
      }
      fn_confirm_field_step: {
        Args: {
          p_byte_size: number
          p_latitude?: number
          p_longitude?: number
          p_order_id: string
          p_qr_token: string
          p_sha256: string
          p_step: string
          p_storage_path: string
        }
        Returns: Json
      }
      fn_create_customer_with_qr: {
        Args: { p_property_id: string }
        Returns: Json
      }
      fn_delete_property: { Args: { p_id: string }; Returns: Json }
      fn_enqueue_handover_reminders: { Args: never; Returns: Json }
      fn_hand_over_settlement: {
        Args: {
          p_byte_size?: number
          p_declared_amount: number
          p_exception_reason?: string
          p_method?: Database["public"]["Enums"]["handover_method"]
          p_note?: string
          p_photo_path?: string
          p_reference?: string
          p_settlement_id: string
          p_sha256?: string
        }
        Returns: Json
      }
      fn_issue_otp: {
        Args: { p_code_hash: string; p_scan_session: string }
        Returns: Json
      }
      fn_launch_readiness: { Args: never; Returns: Json }
      fn_log_tamper_attempt: {
        Args: {
          p_field: string
          p_request_id?: string
          p_scan_session: string
          p_value: string
        }
        Returns: undefined
      }
      fn_mark_otp_sent: {
        Args: { p_challenge_id: string; p_sent: boolean }
        Returns: undefined
      }
      fn_mark_outbox_failed: {
        Args: { p_error_code: string; p_id: number }
        Returns: Json
      }
      fn_mark_outbox_sent: {
        Args: { p_id: number; p_provider_msg_id: string }
        Returns: undefined
      }
      fn_match_bank_deposit: {
        Args: { p_bank_reference: string; p_settlement_id: string }
        Returns: Json
      }
      fn_migration_log: {
        Args: { p_entity?: string }
        Returns: {
          action: string
          created_at: string
          entity: string
          reason: string
          source_id: string
          target_id: string
        }[]
      }
      fn_move_customer_property: {
        Args: { p_customer_id: string; p_property_id: string; p_reason: string }
        Returns: Json
      }
      fn_ops_health: { Args: never; Returns: Json }
      fn_order_notifications: {
        Args: { p_order_id: string }
        Returns: {
          attempts: number
          created_at: string
          id: number
          last_error_code: string
          message: string
          sent_at: string
          state: Database["public"]["Enums"]["outbox_state"]
          template_name: string
        }[]
      }
      fn_outbox_health: { Args: never; Returns: Json }
      fn_payments_awaiting_reconciliation: {
        Args: { p_older_than_minutes?: number }
        Returns: {
          order_no: number
          payment_id: string
          session_id: string
        }[]
      }
      fn_record_cash_payment: { Args: { p_order_id: string }; Returns: Json }
      fn_refresh_reports: { Args: never; Returns: Json }
      fn_reissue_qr: {
        Args: { p_customer_id: string; p_reason: string }
        Returns: Json
      }
      fn_release_invoice: {
        Args: { p_payment_id: string; p_reason: string }
        Returns: Json
      }
      fn_reserve_invoice: {
        Args: {
          p_amount: number
          p_idempotency_key: string
          p_invoice_number: string
          p_order_id: string
        }
        Returns: Json
      }
      fn_reverse_cash_collection: {
        Args: { p_collection_id: string; p_reason: string }
        Returns: Json
      }
      fn_reverse_payment: {
        Args: { p_order_id: string; p_reason: string }
        Returns: Json
      }
      fn_scan_qr: {
        Args: {
          p_ip_hash?: string
          p_request_id?: string
          p_token: string
          p_user_agent?: string
        }
        Returns: Json
      }
      fn_set_customer_active: {
        Args: { p_active: boolean; p_customer_id: string }
        Returns: Json
      }
      fn_set_property_active: {
        Args: { p_active: boolean; p_id: string }
        Returns: Json
      }
      fn_submit_order: {
        Args: {
          p_byte_size: number
          p_sha256: string
          p_storage_path: string
          p_submission_token_hash: string
        }
        Returns: Json
      }
      fn_update_status_setting: {
        Args: {
          p_message: string
          p_notify_enabled: boolean
          p_status: Database["public"]["Enums"]["order_status"]
        }
        Returns: Json
      }
      fn_upsert_property: {
        Args: {
          p_address?: string
          p_code: string
          p_id: string
          p_latitude?: number
          p_longitude?: number
          p_name: string
        }
        Returns: Json
      }
      fn_verify_otp: {
        Args: {
          p_code_hash: string
          p_scan_session: string
          p_submission_token_hash: string
        }
        Returns: Json
      }
      fn_verify_settlement: {
        Args: {
          p_confirmed_amount: number
          p_settlement_id: string
          p_variance_reason?: string
        }
        Returns: Json
      }
      health_check: { Args: never; Returns: Json }
      mask_phone: { Args: { p_phone: string }; Returns: string }
      order_transition_allowed: {
        Args: {
          from_status: Database["public"]["Enums"]["order_status"]
          to_status: Database["public"]["Enums"]["order_status"]
        }
        Returns: boolean
      }
      outbox_backoff: { Args: { p_attempt: number }; Returns: string }
      outbox_max_attempts: { Args: never; Returns: number }
      role_rank: {
        Args: { r: Database["public"]["Enums"]["staff_role"] }
        Returns: number
      }
      setting_int: {
        Args: { p_default: number; p_key: string }
        Returns: number
      }
      tolerance_limit: { Args: never; Returns: number }
      weekend_isodow: { Args: never; Returns: number[] }
      working_days_between: {
        Args: { d1: string; d2: string }
        Returns: number
      }
    }
    Enums: {
      handover_method:
        | "bank_deposit"
        | "transfer"
        | "office_handover"
        | "safe_drop"
      order_status:
        | "new"
        | "confirmed"
        | "picked_up"
        | "processing"
        | "ready"
        | "out_for_delivery"
        | "completed"
        | "cancelled"
      otp_state:
        | "pending"
        | "sent"
        | "verified"
        | "failed"
        | "blocked"
        | "expired"
        | "superseded"
      outbox_state:
        | "pending"
        | "sending"
        | "sent"
        | "failed"
        | "skipped"
        | "dead"
      payment_method: "thawani" | "cash_on_delivery" | "manual"
      payment_status: "unpaid" | "paid" | "refunded"
      photo_kind: "intake" | "pickup" | "delivery" | "cash_handover"
      profile_status: "incomplete" | "complete"
      settlement_state: "open" | "handed_over" | "verified" | "disputed"
      staff_role: "courier" | "operator" | "manager" | "admin"
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
    Enums: {
      handover_method: [
        "bank_deposit",
        "transfer",
        "office_handover",
        "safe_drop",
      ],
      order_status: [
        "new",
        "confirmed",
        "picked_up",
        "processing",
        "ready",
        "out_for_delivery",
        "completed",
        "cancelled",
      ],
      otp_state: [
        "pending",
        "sent",
        "verified",
        "failed",
        "blocked",
        "expired",
        "superseded",
      ],
      outbox_state: ["pending", "sending", "sent", "failed", "skipped", "dead"],
      payment_method: ["thawani", "cash_on_delivery", "manual"],
      payment_status: ["unpaid", "paid", "refunded"],
      photo_kind: ["intake", "pickup", "delivery", "cash_handover"],
      profile_status: ["incomplete", "complete"],
      settlement_state: ["open", "handed_over", "verified", "disputed"],
      staff_role: ["courier", "operator", "manager", "admin"],
    },
  },
} as const

