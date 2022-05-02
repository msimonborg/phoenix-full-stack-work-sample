# Notes

## Scope of work

It took me between three to four hours to familiarize myself with the codebase and the GraphQL API payload that I would need,
and then implement the basic status feature. This core feature provided information on the running deployment (or latest
finished deployment) and a table listing the running instances, with full parity with the `flyctl status` command. All of the
data refreshes every 5 seconds so you can track live changes and deployment progress.

I was enjoying the project and this was my first time working with a GraphQL API so I challenged myself to learn how
to do more than a basic query. As a new user of Fly.io there were a few features I thought of that I could implement which would
be useful for developers managing their deployments. I spent an additional four to six hours learning the GraphQL API and 
implementing these features:

  * Scale VM size and count
  * Restart individual instances
  * Suspend and resume all running processes

## What's not there

If I continued work on this I would want to add the following features to the `app/show` page:

  * Add and remove regions
  * Set auto-scaling rules
  * Set ENV secrets
  * Telemetry monitoring
  * Destroy app
  * View logs (not sure how to do this but it would be fun to try!)

The CLI is powerful and fully featured, and I would want to bring more of that power and observability to the UX in the browser.

Architecturally, I considered writing the status feature as its own child live view, to make the dashboard panes more modular and
reusable. However, without a clear need or request for this type of modularity I decided to avoid the added complexity and add
the feature as an integrated part of the `FlyWeb.AppLive.Show` view.

## Possible improvements and enhancements

If I had more time to spend on this project I would make the following improvements and optimizations to the current code:

  * Remove the unnecessary cruft from the API query payloads
  * Refactor the API `Fly.Client` module to reduce code repetition and improve readability
  * Refactor HTML renders into reusable components, particularly icons, tables, input elements, and buttons
  * Add a `Task.Supervisor` to the application tree and start the API call tasks under supervision
  * Improve error handling of API calls in the view
  * Improve vertical alignment of the release history panel
  * Make the page layout more friendly to mobile and small screen sizes
  * I had an issue wrapping all of the VM scaling management into a single LiveView form component, I believe because the inputs were
  nested under different table data cells. To get around this I wrapped each input and the submit button into its own form and tracked
  input changes in the process state with `phx-change`, then fetched those input values from the state upon `phx-submit`. I would have
  liked to figure out how to wrap all of the elements into a single form to reduce complexity and activity over the socket.

I'm sure there are plenty more improvements that are not presently coming to mind!

## Measuring success

Here are some ways I might measure the success of this feature:

  * Use it myself - as a Fly.io user with my own deployments to manage, this would be one of my most constant sources of feedback
  * Is it simple and intuitive to use and do the features provide value?
  * Full end to end testing
  * If I had access to metrics of the GraphQL API I would track the comparison of dashboard traffic to overall API traffic over time as
  an approximation of utilization.
  * I would consider adding a feature that enables a user to report issues and provide feedback

  ## Possible bug in API

  While testing my features I came across what appears to be a bug in the API. It's apparently possible to scale your VM count while
  the app is in `"suspended"` status. The app will be running and responsive, reachable by HTTP request to its URL, but the status
  will remain "suspended". You can further scale the VM count to whatever arbitrary value you want, although scaling VM size will not
  work until the app is resumed.

  Steps to reproduce:

  * Suspend an app with the `pauseApp` mutation
  * Wait for VMs to spin down
  * Scale the VM count with the `setVmCount` mutation. Your desired number of VMs will spin back up and respond to requests,
  but the app status remains `"suspended"`
  * Setting the VM size with the `setVmSize` mutation will not work
  * Resume the app with the `resumeApp` mutation
  * Existing VMs will continue running and app status instantly changes to `"running"`
  * Setting VM size now works as expected