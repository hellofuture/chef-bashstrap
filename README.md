chef-bashstrap
==============

The purpose of this repo is to help you easily create bash scripts that allow the creation, management and continuing maintenance of servers and cloud instances with Chef.

There a better methods for achieving this at scale but when managing a single server for a personal project or  a couple of servers for client we've found this pattern really helpful. These scripts act as a simple wrapper around knife and relevant aws cli commands and allow you to distribute a straightforward script for updating your instances with Chef.

If you've found yourself writing an update.sh script that runs knife with the various command line arguments you need then this might come in handy. The scripts also helps keep various secrets out of your scripting and therefore out of your repositories.

**THIS IS NOT READY FOR YOU TO USE YET**

**WE NEED TO IRON OUT A FEW BUGS RELATED TO VPC AND WRITE SOME SENSIBLE EXAMPLES**


