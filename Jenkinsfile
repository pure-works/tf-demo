pipeline {
    agent any
    stages {
        stage('checkout') {
            steps {
                checkout scm
                sh 'echo "Checkout Successful"'
            }

        }
        stage('terraform plan & apply') {
            steps {
                sh './tfmain'
            }
        }
        stage('infra-tests') {
            steps {
                sh 'echo "This is from testing stage"'
            } 
        }
    }
}