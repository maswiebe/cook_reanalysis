*-------------------------------------------------------------------------------
* Stata code for replicating Cook (2014)
*-------------------------------------------------------------------------------

* uncomment line below and set path to directory containing this file
*global root "/path/to/dir/"

global data "$root/data"
global tables "$root/output/tables"
global figures "$root/output/figures"

*-------------------------------------------------------------------------------
*** clean population data
*-------------------------------------------------------------------------------

* raw population data from Census:
  * https://www.census.gov/content/dam/Census/library/working-papers/2002/demo/POP-twps0056.pdf
  * Table 1, columns for white and black
* $data/population_excl_indian excludes Indian territory in 1890
* $data/population_incl_indian includes Indian territory in 1890

import delimited "$data/population.csv", clear

*** keep value including indian territory in 1890
  * larger pop
preserve
drop if year==1890 & population == 62622250
tsset year
tsfill, full

* constant carryforward
carryforward pop*, gen(population_const popwhite_const popblack_const)

* linear interpolation
ipolate population year , gen(population_inter)
ipolate pop_white year , gen(popwhite_inter)
ipolate pop_black year , gen(popblack_inter)

save "$data/population_incl_indian",replace
restore

*** keep value excluding indian territory in 1890
  * smaller pop
preserve
drop if year==1890 & population == 62947714
tsset year, delta(10)
gen growth = D.pop_black/L.pop_black
gen ann_growth = (pop_black /L.pop_black)^(1/10) -1
tsset year
tsfill, full

* constant carryforward
carryforward population pop_white pop_black, gen(population_const popwhite_const popblack_const)

* fill backwards
gsort -year
carryforward population pop_white pop_black, gen(population_const_back popwhite_const_back popblack_const_back)
carryforward ann_growth, replace
sort year

* linear interpolation
ipolate population year , gen(population_inter)
ipolate pop_white year , gen(popwhite_inter)
ipolate pop_black year , gen(popblack_inter)

* exponential growth
gen popblack_exp = pop_black
forvalues j = 187/193 {
  forvalues i = 1/9 {
      replace popblack_exp = popblack_exp[_n-1]*(1+ann_growth) if year==real(string(`j')+string(`i'))
    }
}

save "$data/population_excl_indian",replace
restore

*-------------------------------------------------------------------------------
*** patent variable from panel data
*-------------------------------------------------------------------------------

use "$data/pats_state_regs_AAonly.dta", clear
* grant-year patents (table 7)
collapse (sum) patent, by(year)
rename patent patent_panel
save "$data/patent_panel.dta"

* application-year patents (table 9)
use "$data/pats_state_regs_wcontrol.dta", clear
collapse (sum) patent if race==1, by(year)
rename patent patent_t9
save "$data/patent_tab9.dta", replace

*-------------------------------------------------------------------------------
*** Data irregularities
*-------------------------------------------------------------------------------
* use aggregate panel data grant-year patents (total=702) as well as time series patents (total=672)

use "$data/pats_time_series.dta", clear
merge m:1 year using "$data/patent_panel.dta"
drop _merge

* use excluding-indian for blacks
merge m:1 year using "$data/population_excl_indian"
drop _merge
rename popblack_exp excl_popblack_exp
drop pop*
rename excl_popblack_exp popblack_exp

* use including-indian for whites
merge m:1 year using "$data/population_incl_indian"
drop _merge

merge m:1 year using "$data/pats_fig2_fig3.dta"
drop if year<1870
drop _merge

tsset race year

gen lpatapppc = log(pat_appyear_pm)
lab var Dllynchpc "Lynchings"
lab var seglaw "Segregation laws"

gen patgrant_panel = (patent_panel/popblack_exp)*1000000
* grant-year patents per million
* use exponentially interpolated black population
gen lpatgrant_panel = log(patgrant_panel)
replace lpatgrant_panel = lpatgrntpc if race==0
* no changes to make for white patents

gen pg_const_w = patgrntpc*popwhite_const/1000000
* grant-year patents, constant imputation using white population
gen patgrant_fix = (pg_const_w/popblack_exp)*1000000 if race==1
* fix: use exponential interpolation and black population
gen lpatgrant_fix = log(patgrant_fix)

*bro year pg_const_w patent_panel if race==1
*tw line patent_panel pg_const_w year if race==1
* I get integer values, confirming that Cook used the white population (and constant imputation) to calculate black patents per million

preserve
collapse (sum) pg_const_w patent_panel  if race==1
su
* 672 time series patents, 702 panel data patents
restore

lab var patgrntpc "Time series"
lab var patgrant_panel "Panel"
lab var patgrant_fix "Time series (fixed)"
* graph: original patgrant, fixed (use black pop instead of white), aggregate panel (black pop)

set scheme plotplainblind
tw line patgrant_panel patgrntpc patgrant_fix year if race==1, title("") xtitle("") ytitle("Patents per million") legend(pos(6) order(2 3 1) rows(1))
graph export "$figures/grant_year_color.png", replace
graph export "$figures/grant_year_color.pdf", replace
graph export "$figures/grant_year_color.eps", replace

*-------------------------------------------------------------------------------
*** note: application-year patents is more consistent between time series and panel data
* (application-year differs from grant-year, because for the same patent, application and grant occurs in different years)
preserve
keep if race==1

merge 1:1 year using "$data/patent_tab9.dta"
drop _merge

gen pa_const_w = pat_appyear_pm*popwhite_const/1000000
* no
gen pa_const_b = pat_appyear_pm*popblack_const/1000000
* integer values during multiples of ten! she interpolated

gen pa_inter_exp_b = pat_appyear_pm*popblack_exp/1000000
* for application-year, use black population with exponential interpolation
  * get integer values

bro year pa_inter_exp_b patent_t9
* t9 is 1 patent lower in 1896, 1899, and 1921
* fig2: 715; table9: 712
tw line pa_inter_exp_b patent_t9 year

restore

*-------------------------------------------------------------------------------
*** Time series regressions
*-------------------------------------------------------------------------------

tsset race year

*** Table 1: application and three grant-year variables
est clear
qui reg D.lpatapppc Dllynchpc riot seglaw DLMRindex _iyear_1921  t DG1899 _iyear_1910 _iyear_1913 _iyear_1928 if race==1 & year<1940, robust
est sto m1
qui reg D.lpatgrntpc Dllynchpc riot seglaw DLMRindex _iyear_1921  t DG1899 _iyear_1910 _iyear_1913 _iyear_1928 if race==1 & year<1940, robust
est sto m2
qui reg D.lpatgrant_fix Dllynchpc riot seglaw DLMRindex _iyear_1921  t DG1899 _iyear_1910 _iyear_1913 _iyear_1928 if race==1 & year<1940, robust
est sto m3
qui reg D.lpatgrant_panel Dllynchpc riot seglaw DLMRindex _iyear_1921  t DG1899 _iyear_1910 _iyear_1913 _iyear_1928 if race==1 & year<1940, robust
est sto m4
qui reg D.lpatgrntpc Dllynchpc riot seglaw L.Dllynchpc L.riot L.seglaw DLMRindex _iyear_1921  t DG1899 _iyear_1910 _iyear_1913 _iyear_1928 if race==1 & year<1940, robust
est sto m5
qui reg D.lpatgrant_fix Dllynchpc riot seglaw L.Dllynchpc L.riot L.seglaw DLMRindex _iyear_1921  t DG1899 _iyear_1910 _iyear_1913 _iyear_1928 if race==1 & year<1940, robust
est sto m6
qui reg D.lpatgrant_panel Dllynchpc riot seglaw L.Dllynchpc L.riot L.seglaw DLMRindex _iyear_1921  t DG1899 _iyear_1910 _iyear_1913 _iyear_1928 if race==1 & year<1940, robust
est sto m7

esttab m*, mtitle("Application" "Grant: time series" "Grant: fixed" "Grant: panel" "Grant: time series" "Grant: fixed" "Grant: panel") label replace order(Dllynchpc riot seglaw L.Dllynchpc L.riot L.seglaw _iyear_1921) keep(riot Dllynchpc seglaw L.riot L.Dllynchpc L.seglaw _iyear_1921) se r2 star(* 0.1 ** 0.05 *** 0.01) b(%9.3f)
esttab m* using "$tables/t6_timing_all.tex", mtitle("Application" "Grant: time series" "Grant: fixed" "Grant: panel" "Grant: time series" "Grant: fixed" "Grant: panel") label replace order(Dllynchpc riot seglaw L.Dllynchpc L.riot L.seglaw _iyear_1921) keep(riot Dllynchpc seglaw L.riot L.Dllynchpc L.seglaw _iyear_1921) se r2 star(* 0.1 ** 0.05 *** 0.01) b(%9.3f)

*** Table 2: effect of 1921 Tulsa riot
gen d1919 = (year==1919)
gen d1920 = (year==1920)
gen d1922 = (year==1922)
gen d1923 = (year==1923)
lab var d1919 "1919 dummy"
lab var d1920 "1920 dummy"
lab var d1922 "1922 dummy"
lab var d1923 "1923 dummy"

est clear
qui reg D.lpatapppc Dllynchpc riot seglaw DLMRindex d1919 d1920 _iyear_1921 d1922 d1923 t DG1899 _iyear_1910 _iyear_1913 _iyear_1928 if race==1 & year<1940, robust
est sto m1
qui reg D.lpatgrntpc Dllynchpc riot seglaw DLMRindex d1919 d1920 _iyear_1921 d1922 d1923 t DG1899 _iyear_1910 _iyear_1913 _iyear_1928 if race==1 & year<1940, robust
est sto m2
qui reg D.lpatgrant_fix Dllynchpc riot seglaw DLMRindex d1919 d1920 _iyear_1921 d1922 d1923 t DG1899 _iyear_1910 _iyear_1913 _iyear_1928 if race==1 & year<1940, robust
est sto m3
qui reg D.lpatgrant_panel Dllynchpc riot seglaw DLMRindex d1919 d1920 _iyear_1921 d1922 d1923 t DG1899 _iyear_1910 _iyear_1913 _iyear_1928 if race==1 & year<1940, robust
est sto m4
esttab m1 m2 m3 m4, mtitle("Application" "Grant: time series" "Grant: fixed" "Grant: panel") label replace order(Dllynchpc riot seglaw d1919 d1920 _iyear_1921 d1922 d1923) keep(riot Dllynchpc seglaw d1919 d1920 _iyear_1921 d1922 d1923) se r2 star(* 0.1 ** 0.05 *** 0.01) b(%9.3f) 
esttab m1 m2 m3 m4 using "$tables/d1921_all.tex", mtitle("Application" "Grant: time series" "Grant: fixed" "Grant: panel") label replace order(Dllynchpc riot seglaw d1919 d1920 _iyear_1921 d1922 d1923) keep(riot Dllynchpc seglaw d1919 d1920 _iyear_1921 d1922 d1923) se r2 star(* 0.1 ** 0.05 *** 0.01) b(%9.3f) 

*-------------------------------------------------------------------------------
*** Panel data regressions
*-------------------------------------------------------------------------------

*-------------------------------------------------------------------------------
* calculating completely balanced panel
* https://en.wikipedia.org/wiki/List_of_U.S._states_by_date_of_admission_to_the_Union
* https://www.statista.com/statistics/1043617/number-us-states-by-year/

use "$data/pats_state_regs_wcontrol.dta", clear
labelbook

* don't have state names, so need to manually copy label values
  * order them by entry year (year admitted into US)

/*
pre-1870: 38 including DC
8 DE
39 PA
31 NJ
11 GA
7 CT
22 MA
21 MD
41 SC
30 NH
47 VA
33 NY
34 NC
40 RI
46 VT
18 KY
43 TN
36 OH
19 LA
15 IN
25 MS
14 IL
1 AL
20 ME
26 MO
4 AR
23 MI
10 FL
44 TX
16 IA
50 WI
5 CA
24 MN
38 OR
17 KS
49 WV
29 NV
28 NE
9 DC
* Cook has DC from 1871

post-1870
1876:
6 CO

1889:
35 ND
42 SD
27 MT
48 WA

1890:
13 ID
51 WY

1896:
45 UT

1907:
37 OK

1912:
32 NM
3 AZ

1959:
2 AK
12 HI
*/

use "$data/pats_state_regs_AAonly.dta", clear
preserve
collapse stateno, by(year)

gen complete_panel = 38 if year<1876
replace complete_panel = 39 if year>=1876 & year<1889
replace complete_panel = 43 if year>=1889 & year<1890
replace complete_panel = 45 if year>=1890 & year<1896
replace complete_panel = 46 if year>=1896 & year<1907
replace complete_panel = 47 if year>=1907 & year<1912
replace complete_panel = 49 if year>=1912

collapse (sum) complete_panel
su
* 3210
restore

* complete panel sample size: 3210
  * 1870-1940, span of 71 years
* (1876-1870)*38 + (1889-1876)*39 + (1890-1889)*43 + (1896-1890)*45 + (1907-1896)*46 + (1912-1907)*47 + (1941-1912)*49


*-------------------------------------------------------------------------------
*** plot number of observations by state and year

use "$data/pats_state_regs_AAonly.dta", clear

* observations by state
preserve
collapse (count) count=year, by(stateno)
set scheme plotplainblind
scatter count stateno, xtitle("State ID") ytitle("") 
graph export "$figures/obs_state_color.eps", replace
graph export "$figures/obs_state_color.png", replace
graph export "$figures/obs_state_color.pdf", replace
restore

* observations by year
preserve
collapse (count) count=stateno, by(year)
set scheme plotplainblind
scatter count year, xtitle("") ytitle("") 
graph export "$figures/obs_year_color.eps", replace
graph export "$figures/obs_year_color.png", replace
graph export "$figures/obs_year_color.pdf", replace
restore

*-------------------------------------------------------------------------------
*** plot number of observations by region, for actual data and complete and balanced panel

* calculating complete and balanced panel by region
use "$data/pats_state_regs_AAonly.dta", clear

* fix errors
* state 9 has regmatl=0.33 and regs=1 in 1888; regs=1 for all other years
replace regmatl=0 if year==1888 & stateno==9
* state 14 is regmw=1, except for 1886 when it's regmw=0.5 and regs=0.5
replace regs=0 if year==1886 & stateno==14
replace regmw=1 if year==1886 & stateno==14

gen region = .
replace region = 1 if (regs==1)
replace region = 2 if (regmw==1)
replace region = 3 if (regne==1)
replace region = 4 if (regw==1)
replace region = 5 if (regmatl==1)
label define reg_label 1 "South" 2 "Midwest" 3 "Northeast" 4 "West" 5 "Mid-Atlantic"
label values region reg_label

* from wikipedia, linked above
gen entry_year = .
replace entry_year = 1870 if stateno==8 | stateno==39 | stateno==31 | stateno==11 | stateno==7 | stateno==22 | stateno==21 | stateno==41 | stateno==30 | stateno==47 | stateno==33 | stateno==34 | stateno==40 | stateno==46 | stateno==18 | stateno==43 | stateno==36 | stateno==19 | stateno==15 | stateno==25 | stateno==14 | stateno==1 | stateno==20 | stateno==26 | stateno==4 | stateno==23 | stateno==10 | stateno==44 | stateno==16 | stateno==50 | stateno==5 | stateno==24 | stateno==38 | stateno==17 | stateno==49 | stateno==29 | stateno==28 | stateno==9
replace entry_year = 1876 if stateno==6
replace entry_year = 1889 if stateno==35 | stateno==42 | stateno==27 | stateno==48
replace entry_year = 1890 if stateno==13 | stateno==51
replace entry_year = 1896 if stateno==45
replace entry_year = 1907 if stateno==37
replace entry_year = 1912 if stateno==32 | stateno==3

gen duration = 1941-entry_year

preserve
* duration by state and region
collapse duration, by(stateno region)
* total duration by region
collapse (sum) duration, by(region)
bro
* numbers for complete_balanced
restore

preserve
collapse (count) count=stateno, by(region)

* manually grab numbers from browse above
gen complete_balanced = 1028 if region==1
replace complete_balanced = 833 if region==2
replace complete_balanced = 426 if region==3
replace complete_balanced = 639 if region==4
replace complete_balanced = 426 if region==5

lab var count "Actual data"
lab var complete_balanced "Balanced panel"

* Observations by region
set scheme plotplainblind
tw (scatter count region, xlabel(1 "South" 2 "Midwest" 3 "Northeast" 4 "West" 5 "Mid-Atlantic") xtitle("") ytitle("Actual data", axis(1)) yaxis(1)) (scatter complete_balanced region, yaxis(2) ytitle("Balanced panel", axis(2))), legend(pos(6))
graph export "$figures/obs_region_color.eps", replace
graph export "$figures/obs_region_color.png", replace
graph export "$figures/obs_region_color.pdf", replace

restore

*-------------------------------------------------------------------------------
*** Compare panel data to time series
*-------------------------------------------------------------------------------

use "$data/pats_time_series.dta", clear
collapse (sum) riot seglaw if race==1
su
* 35 riots, 290 seglaws

use "$data/pats_state_regs_AAonly.dta", clear
collapse (sum) riot seglaw
su
* 5 riots, 19.33 seglaws

*-------------------------------------------------------------------------------
*** Table 3
*-------------------------------------------------------------------------------

*** create dataset for variables missing in either grant-year or application-year data

*** estbnumpc
use "$data/pats_state_regs_wcontrol.dta", clear
su year gyear
* no applications or grants before 1873
  * but in pats_state_regs_AAonly.dta there are 8 state-year obs with patents in 1870-72
replace gyear = year if missing(gyear)
* these obs have 0 patents
keep gyear stateno estbnumpc 
rename gyear year
collapse estbnumpc, by(stateno year)
save "$data/estbnumpc.dta", replace

*** black share
* Cook's data has many missing observations; to fill these in, I assign the modal value per decade to all years within a decade. Almost all values within a decade are the same.
* It's possible to reconstruct the variable from the raw population data.
  * need state-year-race population
  * https://www.census.gov/content/dam/Census/library/working-papers/2002/demo/POP-twps0056.pdf

use "$data/pats_state_regs_AAonly.dta", clear

keep year stateno blksh
fillin stateno year

gen decade = .
replace decade = 1 if inrange(year, 1870,1879)
replace decade = 2 if inrange(year, 1880, 1889)
replace decade = 3 if inrange(year, 1890, 1899)
replace decade = 4 if inrange(year, 1900, 1909)
replace decade = 5 if inrange(year, 1910, 1919)
replace decade = 6 if inrange(year, 1920, 1929)
replace decade = 7 if inrange(year, 1930, 1939)
replace decade = 8 if inrange(year, 1940, 1949)

egen decade_blksh = mode(blksh ), by(decade stateno)


gen tag=1 if blksh != decade_blksh  & missing(blksh )==0
* not consistent within decade for some observations

keep year stateno decade_blksh
rename decade_blksh blksh

save "$data/blksh.dta", replace

*-------------------------------------------
use "$data/pats_state_regs_AAonly.dta", clear
merge 1:1 stateno year using "$data/estbnumpc.dta"
drop if _merge ==2
drop _merge

xtset stateno year

est clear
qui: xtreg patent riot illit estbnumpc blksh  regs regmw regne regw year1910 year1913 year1928, re  vce(cl stateno)
est sto m1
* 430 obs in dataset, 422 obs in regression: missing 8 obs from 1870-72, since estbnumpc is not defined

tab riot if e(sample)
* 5 riots in sample

qui: xtreg patent riot L.riot illit estbnumpc blksh  regs regmw regne regw year1910 year1913 year1928, re  vce(cl stateno)
est sto m3
tab riot if e(sample)
* only 2 riots in this regression

* application year
use "$data/pats_state_regs_wcontrol.dta", clear
keep if race==1
collapse (sum) patent assn mech elec patsth (mean)  lynchpc2  riot seglaw2 illit regmatl regs regmw regne regw estbnumpc, by(stateno year)
xtset stateno year

gen year1910 = (year==1910)
gen year1913 = (year==1913)
gen year1928 = (year==1928)

merge 1:1 stateno year using "$data/blksh.dta"
drop if _merge==2
drop _merge

qui: xtreg patent riot illit estbnumpc blksh  regs regmw regne regw year1910 year1913 year1928, re  vce(cl stateno)
est sto m2
* 439 obs in dataset, 433 obs in regression: missing 6 obs because blksh is missing
  * 10/FL 1928, 11/GA 1909, 14/IL 1919, 26/MO 1919, 42/SD 1918, 43/TN 1919
  * just because of the imbalanced panel, and blkshare is only defined for years with applications, so missing grant years

tab riot if e(sample)
* 4 riots in sample

lab var riot "Major riots"
lab var illit "Illiteracy rate"
lab var estbnumpc "Number of firms"

esttab m1 m2 m3, mtitle("Grant" "Application" "Grant") label replace order(riot L.riot) keep(riot L.riot) se star(* 0.1 ** 0.05 *** 0.01) b(%9.3f)
esttab m1 m2 m3 using "$tables/t7_timing.tex", mtitle("Grant" "Application" "Grant") label replace order(riot L.riot) keep(riot L.riot) se star(* 0.1 ** 0.05 *** 0.01) b(%9.3f)
* note: esttab doesn't store R2 from xtreg, re (random effects)

*-------------------------------------------------------------------------------
*** other results
*-------------------------------------------------------------------------------

*---------------------
*** 12 states with patent=0; each has two observations, one in 1900 and one in 1930.

use "$data/pats_state_regs_AAonly.dta", clear

tab patent
tab year if patent==0
bro if patent==0
* 24 obs with patent=0, in 1900 and 930

preserve
collapse (sum) patent, by(stateno)
count if patent==0
* 12 states with 0 patents
restore

*---------------------
*** Table 9 says 714 patents, but only 712 in the data
use "$data/pats_state_regs_wcontrol.dta", clear

tab patent if race==1
* 712 patents
* again have 24 obs with patent=0

tab patent if race==0
* onl 706 patents for whites

* p.241: "Specifically, I draw a random sample of 714 patents by application year of patents by African American inventors from the USPTO database using Google Patents."

*---------------------
*** time gap between applications and grants
gen lag = gyear - year 
ttest lag, by (race)
* see fn 15: 1.4 for whites and blacks

*---------------------
*** different violence variables in grant-year and application-year data

* segregation laws: annual in grant data, cumulative in application data

use "$data/pats_state_regs_AAonly.dta", clear
bro year stateno seglaw

use "$data/pats_state_regs_wcontrol.dta", clear
codebook seglaw2
keep if race==1
collapse (sum) patent assn mech elec patsth (mean)  lynchpc2  riot seglaw2 illit regmatl regs regmw regne regw estbnumpc, by(stateno year)
bro year stateno seglaw2

* lynchings: different, unclear why.
* For example, California (stateno==5) has no lynchings in the Table 7 data, but nonzero lynchings in every year in the Table 9 data.

use "$data/pats_state_regs_AAonly.dta", clear
bro year stateno lynchrevpc if stateno==5
* 0 lynchings

use "$data/pats_state_regs_wcontrol.dta", clear
keep if race==1
collapse (sum) patent assn mech elec patsth (mean)  lynchpc2  riot seglaw2 illit regmatl regs regmw regne regw estbnumpc, by(stateno year)
bro year stateno lynchpc2 if stateno==5
* nonzero lynchings in every year

*-------------------------------------------------------------------------------
*** Table 8
use "$data/pats_state_regs_AAonly.dta", clear

qui xtreg assn lynchrevpc riot seglaw illit blksh ind regs regmw regne regw  grinvent year1910 year1913 year1928, re vce(cl stateno)
est sto t81
qui xtreg mech lynchrevpc riot seglaw illit blksh ind regs regmw regne regw year1910 year1913 year1928, re vce(cl stateno)
est sto t82
qui xtreg elec lynchrevpc riot seglaw illit blksh ind regs regmw regne regw year1910 year1913 year1928, re vce(cl stateno)
est sto t83
qui xtreg patsth lynchrevpc riot seglaw illit blksh ind regs regmw regne regw  year1910 year1913 year1928, re vce(cl stateno)
est sto t84
* Patents: grant year
esttab t81 t82 t83 t84, mtitle("Assigned" "Mechanical" "Electrical" "Southern") label replace order(lynchrevpc riot seglaw illit ind) keep(lynchrevpc riot seglaw) se star(* 0.1 ** 0.05 *** 0.01) b(%9.3f) title("Patents: grant year")
* N is off by one, get slightly different results

*-------------------------------------------------------------------------------
*** Table 9
* Cook's code outputs the negative binomial regression results, but Table 9 reports the average marginal effects
* the code below reports the marginal effects, but they don't match the results in the paper.

use "$data/pats_state_regs_wcontrol.dta", clear
collapse (sum) patent assn mech elec patsth (mean)  lynchpc2  riot seglaw2 illit regmatl regs regmw regne regw estbnumpc, by(stateno race)

***Blacks
preserve

keep if race==1

qui nbreg patent lynchpc2  riot seglaw2 illit regmw regne regs regw estbnumpc, robust nolog
eststo margin: margins, dydx(lynchpc2 riot seglaw2 illit estbnumpc) post
estimates store r1cw

qui nbreg assn lynchpc2  riot seglaw2 illit regmw regne regs regw estbnumpc, robust nolog
eststo margin: margins, dydx(lynchpc2 riot seglaw2 illit estbnumpc) post
estimates store r1cx

qui nbreg mech lynchpc2  riot seglaw2 illit regmw regne regs regw estbnumpc, robust nolog
eststo margin: margins, dydx(lynchpc2 riot seglaw2 illit estbnumpc) post
estimates store r1cy

qui nbreg elec lynchpc2  riot seglaw2 illit regmw regne regs regw estbnumpc, robust nolog
eststo margin: margins, dydx(lynchpc2 riot seglaw2 illit estbnumpc) post
estimates store r1cz

qui nbreg patsth lynchpc2  riot seglaw2 illit estbnumpc, robust nolog
eststo margin: margins, dydx(lynchpc2 riot seglaw2 illit estbnumpc) post
estimates store r1caa

esttab r1cw r1cx r1cy r1cz r1caa, nomtitle label replace order(lynchpc2 riot seglaw2 illit estbnumpc) keep(lynchpc2 riot seglaw2 illit estbnumpc) se star(* 0.1 ** 0.05 *** 0.01) b(%9.3f) title("Black patents")

restore

*** Whites
preserve

keep if race==0

nbreg patent lynchpc2  riot seglaw2 illit regmw regne regs regw estbnumpc, robust nolog
eststo margin: margins, dydx(lynchpc2 riot seglaw2 illit estbnumpc) post
estimates store r0cw

nbreg assn lynchpc2  riot seglaw2 illit regmw regne regs regw estbnumpc, robust nolog
eststo margin: margins, dydx(lynchpc2 riot seglaw2 illit estbnumpc) post
estimates store r0cx

nbreg mech lynchpc2  riot seglaw2 illit regmw regne regs regw estbnumpc, robust nolog
eststo margin: margins, dydx(lynchpc2 riot seglaw2 illit estbnumpc) post
estimates store r0cy

nbreg elec lynchpc2  riot seglaw2 illit regmw regne regs regw estbnumpc, robust nolog
eststo margin: margins, dydx(lynchpc2 riot seglaw2 illit estbnumpc) post
estimates store r0cz

nbreg patsth lynchpc2  riot seglaw2 illit estbnumpc, robust nolog
eststo margin: margins, dydx(lynchpc2 riot seglaw2 illit estbnumpc) post
estimates store r0caa

esttab r0cw r0cx r0cy r0cz r0caa, nomtitle label replace order(lynchpc2 riot seglaw2 illit estbnumpc) keep(lynchpc2 riot seglaw2 illit estbnumpc) se star(* 0.1 ** 0.05 *** 0.01) b(%9.3f) title("Black patents")

restore
