# Tutorial for HADES

This repository contains materials for tutorials on the [Health Analytics Data-to-Evidence Suite(HADES)](https://ohdsi.github.io/Hades/), including slides and exercises.

Here you find the materials for the "*Whirlwind Introduction to Open-Source Analytic Tools*" tutorial during the 2025 OHDSI Europe Symposium.
The materials for the (more hands-on) 2024 tutorial are in the [2024_tutorial branch](https://github.com/OHDSI/Tutorial-Hades/tree/2024_tutorial).


# Agenda

| Start | Topic                                                                        | Duration (minutes) |
|-------|------------------------------------------------------------------------------|--------------------|
| 13:30 | HADES design principles and analytic use cases                               | 30                 |
| 14:00 | Cohort building and cohort diagnostics                                       | 30                 |
| 14:30 | The main HADES analytic packages                                             | 30                 |
| 15:00 | Coffee Break                                                                 | 30                 |
| 15:30 | Parallel exercises: Design a Strategus study or Run a Strategus study        | 80                 |
| 16:50 | Wrap-up                                                                      | 10                 |


# Exercises

You can do the practicals on your own laptop.

## Exercise 1: Design a Strategus study

Download [this slidedeck](https://github.com/OHDSI/Tutorial-Hades/blob/main/slides/DesignAStrategusStudy.pptx) and follow the instructions. 
Write down your answers, and ask the faculty whether you were correct.
For bonus points you can try to design your cohorts in [ATLAS](https://atlas-demo.ohdsi.org/).

## Exercise 2: Run a Strategus study

In this exercise you will configure your machine to run HADES and Strategus. 
You will download an example (simulated) dataset and an example Strategus study, and run the study on the dataset.

For this you'll need to [download the example database](https://drive.google.com/file/d/1l5wq57fAslnoFR2umFQvVZbDiq5IK0UF/view?usp=sharing). 
This may take a while, so perhaps best to initiate the download before you take a break.
The database is a 1-million person sample of SynPUF (Synthetic Public Use Files), converted to the OMOP Common Data Model.
It is provided in DuckDB format, so it can run locally on your machine using the R `duckdb` package.

Follow these instructions on the HADES website to configure your machine:

[How to set up R](https://ohdsi.github.io/Hades/rSetup.html) (Note: if you're using the Posit Cloud you can skip most of this, but you'll still need to configure your GitHub Personal Access Token).

Once you've set up R and have set up the example database, you can clone or download the [Strategus study template repo](https://github.com/ohdsi-studies/StrategusStudyRepoTemplate) to your machine. Open the R project `StrategusStudyRepoTemplate.Rproj` in RStudio - you can do this by double-clicking on the project file or by using the **File** Menu then **Open Project...** from within RStudio. When the project opens, from the console run the command `renv::restore()` and follow the prompts to install HADES and the other required R packages (this will take some time). Once this process is complete, restart your RStudio session (from the RStudio menu: **Session** then **Restart R Session**)

Next we'll run the OHDSI Example study on the 1-million person sample of SynPUF. To do this, you'll need to edit the `StrategusCodeToRun.R` script. Start by changing the `databaseName`, on line 23:

```r
databaseName <- "Synpuf" # Only used as a folder name for results from the study
```

Next comment out the Eunomia `connectionDetails` (by placing a # sign) on line 42:

```r
# connectionDetails <- Eunomia::getEunomiaConnectionDetails()
```
And add the following code to configure the connection ot the Synpuf data. **NOTE:** Change the `server` path to the location of the downloaded Synpuf file:

```r
options("strategus.SelfControlledCaseSeriesModule.getDbSccsDataThreads"=1)
connectionDetails <- DatabaseConnector::createConnectionDetails(
  dbms = "duckdb",
  server = "E:/database-1M_filtered/database-1M_filtered.duckdb"
)
```

Now you can run the full `StrategusCodeToRun.R` to execute the sample study which will use the HADES Strategus modules to run the characterization, estimation and prediction analyses. Once complete, you can review the results in the `results` folder of the project.

We've deployed a Shiny app that will allow you to view the results of this sample study executed against SynPuf here: https://results.ohdsi.org/app/32_TutorialHades.
