terraform {
    backend "s3"{
        bucket = "quantlake-tfstate-049506468119"
        key = "environment/dev/terraform.tfstate"
        region = "us-east-1"
        dynamodb_table = "qauntlake-tfstate-lock"
        encrypt = true
        profile = "quantlake-admin"
    }
}