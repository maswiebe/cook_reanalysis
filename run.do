***
* This script generates tables and figures for the paper:
*   "Can we detect the effects of racial violence on patenting? Reanalyzing Cook (2014)"

* Analyses run on Linux using Stata version 16    

* User must uncomment the following line ("global ...") and set the filepath equal to the folder containing this run.do file 
/* global root "/path/to/dir/" */
global root "/home/michael/Dropbox/replications/cook_reanalysis"

clear
set more off
cap log close
log using "$root/output/log.txt", text replace

* Stata version control
version 16

* All required Stata packages are available in the code/libraries/stata folder
/* tokenize `"$S_ADO"', parse(";")
while `"`1'"' != "" {
  if `"`1'"'!="BASE" cap adopath - `"`1'"'
  macro shift
}
adopath ++ "$root/code/libraries/stata" */

do "$root/code/cook_reanalysis.do"

log close