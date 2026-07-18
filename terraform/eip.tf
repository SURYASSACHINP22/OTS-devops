resource "aws_eip" "devops_server" {
  instance = aws_instance.devops_server.id
  domain   = "vpc"

  tags = merge(
    local.common_tags,
    {
      Name = "ots-devops-eip"
    }
  )
}
