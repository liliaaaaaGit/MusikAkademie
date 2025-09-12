# Code Audit Summary

**Timestamp:** 2025-09-12T22:54:08.024Z

## Issues Found

### Ambiguous contract_id References (19)
- `src/components/forms/ContractForm.tsx:340`: contract_id_param: contract?.id || null
- `src/components/forms/ContractForm.tsx:346`: if (!result?.success || !result.contract_id) {
- `src/components/forms/ContractForm.tsx:364`: .eq('id', result.contract_id)
- `src/components/forms/StudentForm.tsx:346`: contract_id_param: student?.contract?.id || null
- `src/components/forms/StudentForm.tsx:359`: return { id: saveResult.contract_id };
- `src/components/forms/StudentForm.tsx:502`: // NEW: Update student with contract_id if contract was created
- `src/components/forms/StudentForm.tsx:506`: .update({ contract_id: contractId })
- `src/components/modals/DeleteContractConfirmationModal.tsx:42`: .eq('contract_id', contract.id)
- `src/components/modals/LessonTrackerModal.tsx:64`: .eq('contract_id', contract.id)
- `src/components/modals/LessonTrackerModal.tsx:137`: // 2. Prepare lesson updates with proper contract_id preservation
- `src/components/modals/LessonTrackerModal.tsx:153`: contract_id: originalLesson.contract_id, // FIXED: Always include contract_id
- `src/components/modals/LessonTrackerModal.tsx:169`: // 3. Use safe batch update function to prevent contract_id issues
- `src/components/modals/LessonTrackerModal.tsx:199`: contract_id_param: contract.id
- `src/components/modals/LessonTrackerModal.tsx:267`: contract_id_param: contract.id,
- `src/components/tabs/ContractsTab.tsx:461`: .eq('contract_id', baseContract.id)
- `src/lib/actions/contractNotes.ts:5`: _contract_id: contractId,
- `src/lib/supabase.ts:48`: contract_id?: string; // Deprecated, use contracts array
- `src/lib/supabase.ts:124`: contract_id: string;
- `src/lib/supabase.ts:165`: contract_id?: string;

### Duplicate RPC Functions (34)
- `public`: Found in 20250106_two_teachers_per_student.sql, 20250106_two_teachers_per_student.sql, 20250106_two_teachers_per_student.sql, 20250106_two_teachers_per_student.sql, 20250107_add_private_notes.sql, 20250107_add_private_notes_fix.sql, 20250107_add_private_notes_fix.sql, 20250108_direct_fix_ambiguous_contract_id.sql, 20250108_fix_all_notification_triggers.sql, 20250108_fix_ambiguous_contract_id.sql, 20250108_fix_ambiguous_contract_id_simple.sql, 20250108_fix_contract_completion_trigger.sql, 20250108_fix_discount_ids_scalar_error.sql, 20250108_fix_teacher_notes_permissions.sql, 20250108_replace_get_teacher_contract_counts.sql, 20250109_fix_contract_teacher_id.sql, 20250704_fix_discount_ids_parsing.sql, 20250704_rls_contract_operation_log.sql, 20250911_add_cutoff_price_version_utility.sql, 20250911_cohort_pricing_v1.sql, 20250911_cohort_pricing_v1.sql, 20250911_cohort_pricing_v1.sql, 20250911_fix_discount_ids_array_handling.sql, 20250911_fix_teacher_counts_and_cohort.sql, 20250911_fix_teacher_counts_and_cohort.sql, 20250911_fix_variants_rpc_for_new_students.sql, 20250911_price_versioning.sql, 20250911_price_versioning.sql
- `batch_update_lessons`: Found in 20250108_comprehensive_teacher_id_cleanup.sql, 20250108_definitive_batch_update_lessons_fix.sql, 20250108_fix_ambiguous_contract_id_in_batch_update.sql, 20250108_fix_lesson_tracking_teacher_reference.sql, 20250703200000_contract_progress_tracking_fix.sql, 20250705_complete_batch_update_fix.sql, 20250705_comprehensive_lesson_tracking_fix.sql, 20250705_fix_ambiguous_contract_id.sql, 20250705_fix_array_length_error.sql, 20250705_fix_notification_trigger.sql, 20250705_fix_notification_trigger_v2.sql, 20250705_restore_contract_completion_notifications.sql, 20250912_final_batch_update_lessons_fix.sql, 20250912_fix_batch_update_lessons.sql
- `update_contract_attendance`: Found in 20250108_comprehensive_teacher_id_cleanup.sql, 20250108_fix_syntax_error.sql, 20250627132358_smooth_sunset.sql, 20250627134012_patient_morning.sql, 20250627134659_rustic_bonus.sql, 20250630120800_delicate_glitter.sql, 20250630135435_tight_frog.sql, 20250702152841_crimson_bar.sql, 20250702154345_fierce_lagoon.sql, 20250703110847_patient_heart.sql, 20250703180000_comprehensive_contract_fix.sql, 20250703190000_contract_editing_sync_fix.sql, 20250704_contract_fulfillment_fix.sql, 20250912_fixed_minimal_fix_students_teacher_id_references.sql, 20250912_minimal_fix_students_teacher_id_references.sql
- `to`: Found in 20250627083802_restless_ocean.sql, 20250627083802_restless_ocean.sql, 20250627110234_silver_garden.sql, 20250627124415_bitter_voice.sql, 20250627124415_bitter_voice.sql, 20250627124415_bitter_voice.sql, 20250630131431_wild_voice.sql, 20250630131431_wild_voice.sql, 20250630131431_wild_voice.sql, 20250703190000_contract_editing_sync_fix.sql, 20250703200000_contract_progress_tracking_fix.sql, 20250705_create_profile_after_signup.sql
- `get_user_role`: Found in 20250627102040_misty_coast.sql, 20250627124415_bitter_voice.sql
- `generate_bank_id`: Found in 20250627124415_bitter_voice.sql, 20250630131431_wild_voice.sql
- `auto_generate_student_bank_id`: Found in 20250627124415_bitter_voice.sql, 20250630131431_wild_voice.sql, 20250630173655_long_butterfly.sql
- `auto_generate_teacher_bank_id`: Found in 20250627124415_bitter_voice.sql, 20250630131431_wild_voice.sql, 20250630173655_long_butterfly.sql
- `auto_generate_lessons`: Found in 20250627132358_smooth_sunset.sql, 20250630120800_delicate_glitter.sql, 20250703190000_contract_editing_sync_fix.sql
- `accept_trial`: Found in 20250629130810_jade_flame.sql, 20250702132142_mute_grass.sql, 20250702133149_late_mountain.sql
- `calculate_contract_price`: Found in 20250630120800_delicate_glitter.sql, 20250630163451_icy_oasis.sql
- `notify_contract_fulfilled`: Found in 20250630143645_old_torch.sql, 20250630144628_divine_garden.sql, 20250630145151_black_manor.sql, 20250630145442_restless_feather.sql, 20250701135851_silent_bridge.sql, 20250701141716_small_glitter.sql, 20250701151215_solitary_marsh.sql, 20250701152542_stark_band.sql, 20250702143817_flat_mud.sql, 20250702152047_silver_tower.sql, 20250703170000_fix_contract_completion_notification.sql, 20250703180000_comprehensive_contract_fix.sql, 20250704_notification_nonblocking_fix.sql, 20250705_comprehensive_lesson_tracking_fix.sql, 20250705_fix_notification_trigger.sql, 20250705_fix_notification_trigger_v2.sql, 20250705_restore_contract_completion_notifications.sql
- `mark_notification_read`: Found in 20250630143645_old_torch.sql, 20250630144628_divine_garden.sql, 20250630145151_black_manor.sql
- `delete_notification`: Found in 20250630143645_old_torch.sql, 20250630144628_divine_garden.sql, 20250630145151_black_manor.sql
- `update_notification_timestamp`: Found in 20250630143645_old_torch.sql, 20250630144628_divine_garden.sql, 20250630145151_black_manor.sql
- `test_notification_system`: Found in 20250630145442_restless_feather.sql, 20250701135851_silent_bridge.sql, 20250701145340_flat_boat.sql, 20250701151215_solitary_marsh.sql, 20250701152542_stark_band.sql
- `check_notification_system_status`: Found in 20250701135851_silent_bridge.sql, 20250701151215_solitary_marsh.sql
- `force_contract_notification`: Found in 20250701151215_solitary_marsh.sql, 20250705_fix_notification_trigger.sql, 20250705_fix_notification_trigger_v2.sql
- `decline_trial`: Found in 20250702132142_mute_grass.sql, 20250702133149_late_mountain.sql
- `notify_assigned_trial`: Found in 20250702132142_mute_grass.sql, 20250702133149_late_mountain.sql, 20250702141406_ancient_thunder.sql, 20250702142356_rapid_dust.sql, 20250702142932_ancient_truth.sql, 20250702143405_flat_glitter.sql, 20250702145602_bronze_wood.sql, 20250702150304_warm_scene.sql
- `notify_declined_trial`: Found in 20250702132142_mute_grass.sql, 20250702133149_late_mountain.sql, 20250702141406_ancient_thunder.sql, 20250702142356_rapid_dust.sql, 20250702142932_ancient_truth.sql, 20250702143405_flat_glitter.sql, 20250702143817_flat_mud.sql, 20250702145602_bronze_wood.sql, 20250702150304_warm_scene.sql
- `notify_accepted_trial`: Found in 20250702132142_mute_grass.sql, 20250702133149_late_mountain.sql, 20250702141406_ancient_thunder.sql, 20250702142356_rapid_dust.sql, 20250702142932_ancient_truth.sql, 20250702143405_flat_glitter.sql, 20250702143817_flat_mud.sql, 20250702145602_bronze_wood.sql, 20250702150304_warm_scene.sql
- `notify_new_open_trial`: Found in 20250702133149_late_mountain.sql, 20250702141406_ancient_thunder.sql, 20250702142356_rapid_dust.sql, 20250702142932_ancient_truth.sql, 20250702143405_flat_glitter.sql, 20250702145602_bronze_wood.sql, 20250702150304_warm_scene.sql
- `fix_contract_attendance`: Found in 20250702152841_crimson_bar.sql, 20250702154345_fierce_lagoon.sql, 20250703110847_patient_heart.sql, 20250703180000_comprehensive_contract_fix.sql
- `verify_contract_notification_system`: Found in 20250703170000_fix_contract_completion_notification.sql, 20250703180000_comprehensive_contract_fix.sql
- `handle_contract_update`: Found in 20250703190000_contract_editing_sync_fix.sql, 20250703200000_contract_progress_tracking_fix.sql
- `sync_contract_data`: Found in 20250703190000_contract_editing_sync_fix.sql, 20250703200000_contract_progress_tracking_fix.sql
- `log_contract_error`: Found in 20250703200000_contract_progress_tracking_fix.sql, 20250703210000_contract_save_error_fix.sql, 20250703210000_fix_contract_save_errors.sql
- `validate_contract_data`: Found in 20250703210000_contract_save_error_fix.sql, 20250703210000_fix_contract_save_errors.sql
- `safe_save_contract`: Found in 20250703210000_contract_save_error_fix.sql, 20250703210000_fix_contract_save_errors.sql
- `check_contract_permissions`: Found in 20250703210000_contract_save_error_fix.sql, 20250703210000_fix_contract_save_errors.sql
- `diagnose_contract_save_issue`: Found in 20250703210000_contract_save_error_fix.sql, 20250703210000_fix_contract_save_errors.sql
- `create_profile_after_signup`: Found in 20250705_comprehensive_auth_fix.sql, 20250705_create_profile_after_signup.sql, 20250705_fix_profile_creation.sql
- `notify_contract_completion`: Found in 20250912_fixed_minimal_fix_students_teacher_id_references.sql, 20250912_minimal_fix_students_teacher_id_references.sql

