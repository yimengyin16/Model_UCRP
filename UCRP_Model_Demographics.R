# Simulation of the demograhics of UCRP

## Modifications on the original model
#1. Need to calculate the number of LSC claims(by ea, age) for each year. (Can be calculated after the loop) 
#2. Need to calculate the number of new retirees opting for contingent annuity(by ea, age) for each year. (Can be calculated after the loop) 
#3. The mortality for retirees are now retirement age dependent.


get_Population <- function(.init_pop         = init_pop,
                           .entrants_dist    = entrants_dist,
                           .decrement.ucrp   = decrement.ucrp,
                           .paramlist        = paramlist,
                           .Global_paramlist = Global_paramlist){

## Inputs
# - range_ea:         all possible entry ages  
# - range_age:        range of age
# - nyear:            number of years in simulation
# - wf_growth:        growth rate of the size of workforce
# - no_entrance:      no new entrants into the workforce if set "TRUE". Overrides "wf_growth"
# - Decrement table:  from Model_Decrements.R  
# - Initial workforce for each type:
#    - init_pop$actives:   matrix, max ea by max age
#    - init_pop$retirees:  matrix, max ea by max age


## An array is created for each of the 6 status:
#  (1)Active     (dim = 3)
#  (2)Terminated (dim = 4)
#  (3)Retired    (dim = 4)
#  (4)Disabled   (dim = 3) later will be expanded to dim = 4, with additional dim being year.disb
#  (5)Dead       (dim = 3) We do not really need an array for dead, what's needed is only the total number of dead.  

# Run the section below when developing new features.   
   # .init_pop         = init_pop
   # .entrants_dist    = entrants_dist
   # .decrement.ucrp   = decrement.ucrp
#   .paramlist        = paramlist
#   .Global_paramlist = Global_paramlist
# #   
#   

 assign_parmsList(.Global_paramlist, envir = environment())
 assign_parmsList(.paramlist,        envir = environment())  


#*************************************************************************************************************
#                                     Creating arrays for each status ####
#*************************************************************************************************************

## In each 3D array, dimension 1(row) represents entry age, dimension 2(column) represents attained age,
# dimension 3(depth) represents number of year, dimension 4(terms only) represents the termination year. 
wf_dim      <- c(length(range_ea), length(range_age), nyear)
wf_dimnames <- list(range_ea, range_age, init.year:(init.year + nyear - 1))

# The array of terminated has 4 dimensions: ea x age x year x year of termination
wf_dim.term      <- c(length(range_ea), length(range_age), nyear, nyear + 1)
wf_dimnames.term <- list(range_ea, range_age, init.year:(init.year + nyear - 1), (init.year - 1) :(init.year + nyear - 1))


# # The array of retirees has 4 dimensions: ea x age x year x year of retirement
wf_dim.la      <- c(length(range_ea), length(range_age), nyear, nyear)
wf_dimnames.la <- list(range_ea, range_age, init.year:(init.year + nyear - 1), init.year:(init.year + nyear - 1))


wf_active  <- array(0, wf_dim, dimnames = wf_dimnames)
wf_disb    <- array(0, wf_dim, dimnames = wf_dimnames) 
wf_dead    <- array(0, wf_dim, dimnames = wf_dimnames)
wf_term    <- array(0, wf_dim.term,    dimnames = wf_dimnames.term)
wf_la      <- array(0, wf_dim.la, dimnames = wf_dimnames.la)


newDeath.act  <- numeric(nyear)
newDeath.ret  <- numeric(nyear)
newDeath.term <- numeric(nyear)

newDisb.act <- numeric(nyear)


#*************************************************************************************************************
#                                     Setting initial population  ####
#*************************************************************************************************************

# Setting inital distribution of workforce and retirees.
# Note on initial retirees: It is assumed that all initial retirees entered the workforce at age 54 and retireed in year 1. 
# Altough this may produce yos greater than r.max - ea.min, it is irrelevant to the calculation since we do not care about initial retirees' yos.  
# 
wf_active[, , 1]   <- .init_pop$actives 
wf_la[, , 1, 1]    <- .init_pop$retirees
wf_term[, , 1, 1]  <- .init_pop$terms   # note that the initial terms are assigned to year.term = init.year - 1
# 


#*************************************************************************************************************
#                                     Defining population dynamics  ####
#*************************************************************************************************************

## Transition matrices ####

# Assume the actual decrement rates are the same as the rates in decrement tables.
# Later we may allow the actual decrement rates to differ from the assumed rates. 

decrement_wf <- sapply(.decrement.ucrp, function(x){x[is.na(x)] <- 0; return(x)}) %>% data.frame # just for safety


# Define a function that produce transition matrices from decrement table. 
make_dmat <- function(qx, df = decrement_wf) {
  # inputs:
  # qx: character, name of the transition probability to be created.
  # df: data frame, decrement table.
  # returns:
  # a transtion matrix
  df %<>% select_("age", "ea", qx) %>% ungroup %>% spread_("ea", qx, fill = 0) %>% select(-age) %>% t # need to keep "age" when use spread
  dimnames(df) <- wf_dimnames[c(1,2)] 
  return(df)
}

# The transition matrices are defined below. The probabilities (eg. qxr for retirement) of flowing
# from the current status to the target status for a cell(age and ea combo) are given in the corresponding
# cell in the transtition matrices. 

# Where do the active go
p_active2term    <- make_dmat("qxt")
p_active2disb    <- make_dmat("qxd")
p_active2dead    <- make_dmat("qxm.pre")
p_active2retired <- make_dmat("qxr")      # This include all three types of retirement: LSC, contingent annuity, and life annuity.
p_active2la <- make_dmat("qxr.la")   # Prob of retiring as a life annuitant.




# Where do the terminated go
p_term2dead    <- make_dmat("qxm.term") # need to modify later


# Where do the disabled go
p_disb2dead    <- make_dmat("qxm.pre") #need to modify later.



# Where do the retirees go 
# Before we find better approach, the age.r dependent mortality for retirees are given in a data frame containing all combos 
# of year, year.r, ea, and age that exist in wf_la. 

p_la2dead <- expand.grid(ea = range_ea, age = range_age, year = init.year:(init.year + nyear - 1), year.r = init.year:(init.year + nyear - 1)) %>%
  #filter(age >= ea) %>% 
  mutate(age.r = age - (year - year.r)) %>% 
  left_join(mortality.post.ucrp %>% select(age.r, age, qxm.post.W)) %>%
  mutate(qxm.post.W = na2zero(qxm.post.W)) %>% 
  arrange(year, year.r, age, ea)

# x <- (p_retired2dead %>% filter(year == 2015))



# In each iteration, a flow matrix for each possible transition(eg. active to retired) is created 
# (if we wanted to track the flow in each period, we create flow arrays instead of flow matrices)

# Define the shifting matrix. When left mutiplied by a workforce matrix, it shifts each element one cell rightward(i.e. age + 1)
# A square matrix with the dimension length(range_age)
# created by a diagal matrix without 1st row and last coloumn
A <- diag(length(range_age) + 1)[-1, -(length(range_age) + 1)] 




#*************************************************************************************************************
#                                     Creating a function to calculate new entrants ####
#*************************************************************************************************************


# define function for determining the number of new entrants 
calc_entrants <- function(wf0, wf1, delta, dist, no.entrants = FALSE){
  # This function deterimine the number of new entrants based on workforce before and after decrement and workforce 
  # growth rate. 
  # inputs:
  # wf0: a matrix of workforce before decrement. Typically a slice from wf_active
  # wf1: a matrix of workforce after decrement.  
  # delta: growth rate of workforce
  # returns:
  # a matrix with the same dimension of wf0 and wf1, with the number of new entrants in the corresponding cells,
  # and 0 in all other cells. 
  
  # working age
  working_age <- min(range_age):(r.max - 1)
  # age distribution of new entrants
  # dist <- rep(1/nrow(wf0), nrow(wf0)) # equally distributed for now. 
  
  # compute the size of workforce before and after decrement
  size0 <- sum(wf0[,as.character(working_age)], na.rm = TRUE)
  size1 <- sum(wf1[,as.character(working_age)], na.rm = TRUE)
  
  # computing new entrants
  size_target <- size0*(1 + delta)   # size of the workforce next year
  size_hire   <- size_target - size1 # number of workers need to hire
  ne <- size_hire*dist               # vector, number of new entrants by age
  
  # Create the new entrant matrix 
  NE <- wf0; NE[ ,] <- 0
  
  if (no.entrants){ 
    return(NE) 
  } else {
    NE[, rownames(NE)] <- diag(ne) # place ne on the matrix of new entrants
    return(NE)
  } 
}

# test the function 
# wf0 <- wf_active[, , 1]
# wf1 <- wf_active[, , 1]*(1 - p_active2term)
# sum(wf0, na.rm = T) - sum(wf1, na.rm = T)
# sum(calc_entrants(wf0, wf1, 0), na.rm = T)



#*************************************************************************************************************
#                                     Simulating the evolution of population  ####
#*************************************************************************************************************

# Now the next slice of the array (array[, , i + 1]) is defined
# wf_active[, , i + 1] <- (wf_active[, , i] + inflow_active[, , i] - outflow_active[, , i]) %*% A + wf_new[, , i + 1]
# i runs from 2 to nyear. 

for (j in 1:(nyear - 1)){
  #j <-  1  
  # compute the inflow to and outflow
  active2term    <- wf_active[, , j] * p_active2term  # This will join wf_term[, , j + 1, j + 1], note that workers who terminate in year j won't join the terminated group until j+1. 
  active2disb    <- wf_active[, , j] * p_active2disb
  active2dead    <- wf_active[, , j] * p_active2dead
  active2retired <- wf_active[, , j] * p_active2retired    # This will be used to calculate the number of actives leaving the workforce
  active2la      <- wf_active[, , j] * p_active2la          # This will join wf_la[, , j + 1, j + 1].
  
  
  # Where do the terminated_vested go
  term2dead  <- wf_term[, , j, ] * as.vector(p_term2dead)           # a 3D array, each slice(3rd dim) contains the # of death in a termination age group
  
  # Where do the retired go
  la2dead   <- wf_la[, , j, ] * (p_la2dead %>% filter(year == j + init.year - 1))[["qxm.post.W"]]     # as.vector(p_retired2dead) # a 3D array, each slice(3rd dim) contains the # of death in a retirement age group    
  
  # Where do the disabled go
  disb2dead      <- wf_disb[, , j] * p_disb2dead
  
  
  
  # Total inflow and outflow for each status
  out_active   <- active2term + active2disb + active2retired + active2dead 
  new_entrants <- calc_entrants(wf_active[, , j], wf_active[, , j] - out_active, wf_growth, dist = .entrants_dist, no.entrants = no_entrance) # new entrants
  
  out_term <- term2dead    # This is a 3D array 
  in_term  <- active2term  # This is a matrix
  
  out_disb <- disb2dead
  in_disb  <- active2disb
  
  out_la <- la2dead        # This is a 3D array (ea x age x year.retire)
  in_la  <- active2la      # This is a matrix
  
  in_dead <- active2dead +                                        # In UCRP model, since life annuitants are only part of the total retirees, in_dead does not reflect the total number of death. 
    apply(term2dead, c(1,2), sum) + apply(la2dead, c(1,2), sum) + # get a matirix of ea x age by summing over year.term/year.retiree
    disb2dead 
  
  # Calculate workforce for next year. 
  wf_active[, , j + 1]  <- (wf_active[, , j] - out_active) %*% A + new_entrants
  
  wf_term[, , j + 1, ]  <- apply((wf_term[, , j, ] - out_term), 3, function(x) x %*% A) %>% array(wf_dim.term[-3])
  wf_term[, , j + 1, j + 1] <- in_term %*% A     # Note that termination year j = 1 correponds to init.year - 1
  
  wf_la[, ,j + 1, ]       <- apply((wf_la[, , j, ] - out_la), 3, function(x) x %*% A) %>% array(wf_dim.la[-3])
  wf_la[, , j + 1, j + 1] <- in_la %*% A
  
  wf_disb[, ,   j + 1]    <- (wf_disb[, , j] + in_disb - out_disb) %*% A
  wf_dead[, ,   j + 1]    <- (wf_dead[, , j] + in_dead) %*% A
  
  newDeath.act[j]  <- sum(active2dead)
  newDeath.ret[j]  <- sum(la2dead)
  # newDeath.term[j] <- sum()
  
  newDisb.act[j] <- sum(active2disb)
  
}



#*************************************************************************************************************
#                                     Transform Demographic Data to Data Frames   ####
#*************************************************************************************************************

## Convert 3D arrays of actives, retired and terms to data frame, to be joined by liability data frames

wf_active <- adply(wf_active, 3, function(x) {df = as.data.frame(x); df$ea = as.numeric(rownames(x));df}) %>% 
  rename(year = X1) %>%
  gather(age, number.a, -ea, -year) %>% 
  mutate(year = f2n(year), age = as.numeric(age)) %>% 
  filter(age >= ea)


wf_la <- data.frame(expand.grid(ea = range_ea, age = range_age, year = init.year:(init.year + nyear - 1), year.r = init.year:(init.year + nyear - 1)),
                         number.la = as.vector(wf_la)) %>% 
         filter(age >= ea)


wf_term <- data.frame(expand.grid(ea = range_ea, age = range_age, year = init.year:(init.year + nyear - 1), year.term = (init.year-1):(init.year + nyear - 1)),
                      number.v = as.vector(wf_term)) %>% 
  filter(age >= ea)


# summarize term across termination year. Resulting data frame will join .Liab$active as part of the output. 
term_reduced <- wf_term %>% group_by(year, age) %>% summarise(number.v = sum(number.v, na.rm = TRUE))




#*************************************************************************************************************
#                                     Number of members opting for LSC and contingent annuity   ####
#*************************************************************************************************************



wf_LSC.ca <- wf_active %>% left_join(decrement_wf %>% select(age, ea, qxr.LSC, qxr.ca)) %>% 
             mutate(new_LSC = number.a * qxr.LSC,
                    new_ca  = number.a * qxr.ca,
                    year = year + 1,
                    age  = age + 1)






# Final outputs
pop <-  list(active = wf_active, term = wf_term, disb = wf_disb, la = wf_la, dead = wf_dead, LSC.ca = wf_LSC.ca)

return(pop)

}


# pop <- get_Population()






# pop$term %>% filter(year == 2016) %>% select(number.v) %>% sum



# # Spot check the results
# wf_active %>% group_by(year) %>% summarise(n = sum(number.a)) %>% mutate(x = n == 1000) %>% data.frame # OK
# wf_active %>% filter(year == 2025) %>% spread(age, number.a)
# 
# 
# wf_la %>% group_by(year) %>% summarise(n = sum(number.la)) %>% data.frame  
# 
# wf_la %>% filter(year.r == 2016, year == 2018, age==65) %>% mutate(number.la_next = number.la * 0.9945992) %>% 
#   left_join(wf_la %>% filter(year.r == 2016, year == 2019, age==66) %>% select(year.r, ea, number.la_true = number.la)) %>% 
#   mutate(diff = number.la_true - number.la_next) # looks ok.
# 
# mortality.post.ucrp %>% filter(age.r == 63)
# 
# 
# 
# 
# # check retirement
# wf_active %>% filter(year == 2020, ea == 30) %>% select(-year) %>% 
# left_join(wf_la     %>% filter(year == 2021, year.r == 2021, ea == 30)) %>% 
# left_join(wf_LSC.ca %>% filter(year == 2021, ea == 30) %>% select(year, ea, age, new_LSC, new_ca)) %>% 
# left_join(decrement_wf %>% filter(ea == 30) %>% select(ea, age, qxr, qxr.la, qxr.ca, qxr.LSC)) %>% 
# filter(age >= 49 & age <=75) %>% 
# mutate(diff.la = lag(number.a *qxr.la) - number.la,
#        diff.ca = lag(number.a *qxr.ca) - new_ca,
#        diff.LSC= lag(number.a *qxr.LSC) - new_LSC,
#        diff.r  = lag(number.a *qxr) - (new_ca + new_LSC + number.la))
#   # looks ok.
#





# wf_active %>% group_by(year) %>% summarise(n = sum(number.a))
# 
# wf_active %>% head
# 






