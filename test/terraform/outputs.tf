output "instance_id" {
  value = aws_instance.bench.id
}

output "public_ip" {
  value = aws_instance.bench.public_ip
}

output "ami" {
  value = "${local.ami_id} (${data.aws_ami.rocky9.name})"
}

output "spot" {
  value = var.use_spot ? "spot one-time (max price: ${coalesce(local.spot_max_price, "on-demand cap")})" : "on-demand"
}

output "ssh" {
  value = "ssh -i ${local.ssh_private_key} rocky@${aws_instance.bench.public_ip}"
}

output "ssm" {
  value = "aws ssm start-session --region ${var.region} --target ${aws_instance.bench.id}"
}

output "inventory" {
  value = abspath(local_file.inventory.filename)
}
