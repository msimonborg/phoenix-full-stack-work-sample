# Fly.io Full Stack Phoenix Hiring Project

This is a fork of the [Fly.io Full Stack developer hiring project](https://fly.io/blog/fly-io-is-hiring-full-stack-developers/).
The scope of this project is to implement a feature providing the functionality of the `flyctl status` command, which outputs
something like this:

```
$ flyctl status
App
  Name     = flyio-web-staging          
  Owner    = fly                        
  Version  = 118                        
  Status   = running                    
  Hostname = flyio-web-staging.fly.dev  

Deployment Status
  ID          = d2f306ae-803b-fa48-d2f1-7d56a16de9ff         
  Version     = v118                                         
  Status      = successful                                   
  Description = Deployment completed successfully            
  Instances   = 3 desired, 3 placed, 3 healthy, 0 unhealthy  

Instances
ID       TASK   VERSION REGION DESIRED STATUS  HEALTH CHECKS      RESTARTS CREATED   
ed63d501 web    118     iad    run     running 1 total, 1 passing 0        2h38m ago 
38ece520 web    118     iad    run     running 1 total, 1 passing 0        2h39m ago 
3bf5f208 worker 118     iad    run     running                    0        2h39m ago 
```

I implemented this feature and added a few extra for a UX that provides developers with more control over their deployments.

This app uses Phoenix LiveView and is deployed on Fly.io in the `ewr` region. If you have an account with Fly.io you can visit the app at
[https://falling-cherry-5505.fly.dev](https://falling-cherry-5505.fly.dev). Run `flyctl auth token` on your
command line and use the token to login. You can now view the status of your apps, pause/resume them, scale them in both VM size and
count, and restart the running instances.

Checkout [notes.md](notes.md) for a more detailed recap of my work and thoughts on this project.