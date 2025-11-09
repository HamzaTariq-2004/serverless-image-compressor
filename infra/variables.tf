variable "region" {
  type    = string
  default = "ap-south-1"
}

variable "upload_bucket_name" {
  default = "image-compressor-uploads-bucket"
}

variable "compressed_bucket_name" {
  default = "image-compressor-compress-bucket"
}

variable "frontend_bucket_name" {
  default = "image-compressor-frontend-bucket"
}
