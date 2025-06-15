output "folder_structure" {
  value = {
    legacy     = module.org_structure.folder_ids["legacy-systems"]
    migration  = module.org_structure.folder_ids["migration-in-progress"]
    compliant  = module.org_structure.folder_ids["compliant-systems"]
  }
}

output "migration_instructions" {
  value = <<-EOT
    Next Steps:
    1. Move all existing projects to legacy folder: ${module.org_structure.folder_ids["legacy-systems"]}
       Run: ./scripts/move-projects-to-legacy.sh ${module.org_structure.folder_ids["legacy-systems"]}
    
    2. Assess each project for compliance:
       Run: ./scripts/assess-project-compliance.sh PROJECT_ID
    
    3. Create migration plan for each project
    
    4. Move projects through migration folder as they're updated
  EOT
}