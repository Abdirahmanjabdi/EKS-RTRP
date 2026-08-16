variable "project_name" {
  type = string
}
variable "alert_email" {
  type        = string
  description = "Email address to subscribe to the SNS alerts topic"
}