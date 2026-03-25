resource "aws_efs_file_system" "n8n" {
  creation_token = "n8n-efs"
}

resource "aws_efs_mount_target" "n8n" {
  for_each        = toset(var.private_subnet_ids)
  file_system_id  = aws_efs_file_system.n8n.id
  subnet_id       = each.value
  security_groups = [aws_security_group.efs_sg.id]
}
