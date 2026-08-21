output "state_bucket_name" {
  value       = aws_s3_bucket.terraform_state.id
  description = "The name of the S3 bucket storing Terraform state"
}

output "lock_table_name" {
  value       = aws_dynamodb_table.terraform_locks.id
  description = "The name of the DynamoDB table used for state locking"
}