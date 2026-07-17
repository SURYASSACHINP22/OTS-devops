resource "aws_key_pair" "ots_devops" {
  key_name   = "ots-devops-key"
  public_key = file(var.public_key_path)

  tags = merge(
    local.common_tags,
    {
      Name = "ots-devops-key"
    }
  )
}