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
                sh './dpp-tf.sh'
            }
        }
        stage('infra-tests') {
            
        }
    }
}