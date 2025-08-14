import jenkins.model.*
import hudson.security.*

def instance = Jenkins.get()
def currentRealm = instance.getSecurityRealm()
def adminUser = System.getenv("JENKINS_ADMIN_USER") ?: "admin"
def adminPass = System.getenv("JENKINS_ADMIN_PASSWORD") ?: "admin"

if (!(currentRealm instanceof HudsonPrivateSecurityRealm)) {
  def realm = new HudsonPrivateSecurityRealm(false)
  if (realm.getAllUsers().isEmpty()) {
    realm.createAccount(adminUser, adminPass)
  }
  instance.setSecurityRealm(realm)
  def strategy = new FullControlOnceLoggedInAuthorizationStrategy()
  strategy.setAllowAnonymousRead(false)
  instance.setAuthorizationStrategy(strategy)
  instance.save()
}