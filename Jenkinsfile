pipeline {
    agent any

    stages {
        stage('Git checkout') {
            steps {
                checkout([$class: 'GitSCM', branches: [[name: '*/master']], extensions: [], userRemoteConfigs: [[credentialsId: '000f4401-9296-458d-af0a-cbc77504c807', url: 'https://gitee.com/z_true/hexo.git']]])
            }
        }
        stage('Build') {
            steps {
                sh 'echo "Building..."'
                sh 'echo "Build success!"'
            }
        }
        stage('Deploy') {
            agent {
                docker {
                    image 'node:7-alpine'
                }
            }
            steps {
                sh 'echo "Deploy..."'
                sh 'cp -rf * /var/hexo'
//                sh 'npm install'
                sh 'echo "Deploy success!"'
            }
        }
    }
    post {
        always {
            echo 'This will always run'
        }
        success {
            echo 'This will run only if successful'
        }
        failure {
            echo 'This will run only if failed'
            mail to: 'z_true@163.com',
                    subject: "Failed Pipeline: ${currentBuild.fullDisplayName}",
                    body: "Something is wrong with ${env.BUILD_URL}"
        }
        unstable {
            echo 'This will run only if the run was marked as unstable'
        }
        changed {
            echo 'This will run only if the state of the Pipeline has changed'
            echo 'For example, if the Pipeline was previously failing but is now successful'
        }
    }
}

