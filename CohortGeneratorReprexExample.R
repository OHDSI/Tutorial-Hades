# create concept set
library(Capr)
library(dplyr, warn.conflicts = FALSE)

gibleedCohort <- cohort(entry = entry(condition(cs(descendants(192671)))))

cohortTableNames <- CohortGenerator::getCohortTableNames(cohortTable = "my_cohort_table")

connectionDetails <- Eunomia::getEunomiaConnectionDetails()

json <- as.json(gibleedCohort)
sql <- CirceR::buildCohortQuery(CirceR::cohortExpressionFromJson(json), 
                                options =  CirceR::createGenerateOptions(generateStats = FALSE))

cohortsToCreate <- tibble(
  cohortId = 1L:4L,
  cohortName = "gibleed",
  json = json,
  sql = sql) %>%
  mutate(cohortId = bit64::as.integer64(cohortId))

CohortGenerator::isCohortDefinitionSet(cohortsToCreate)

CohortGenerator::createCohortTables(connectionDetails = connectionDetails,
                                    cohortDatabaseSchema = "main",
                                    cohortTableNames = cohortTableNames)

cohortsGenerated <- CohortGenerator::generateCohortSet(connectionDetails = connectionDetails,
                                                       cdmDatabaseSchema = "main",
                                                       cohortDatabaseSchema = "main",
                                                       cohortTableNames = cohortTableNames,
                                                       cohortDefinitionSet = cohortsToCreate[1,])




