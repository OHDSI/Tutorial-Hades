# get shiny server and R from the rocker project
FROM ohdsi/broadsea-shiny:1.2.0

# JNJ Specific 
# RUN apt-get install -y ca-certificates
# COPY ZscalerRootCA.crt /root/ZscalerRootCA.crt
# RUN cat /root/ZscalerRootCA.crt >> /etc/ssl/certs/ca-certificates.crt
# COPY ZscalerRootCA.crt /usr/local/share/ca-certificates
# RUN update-ca-certificates

# Set an argument for the app name and port
ARG APP_NAME
ARG SHINY_PORT

# Set arguments for the GitHub branch and commit id abbreviation
ARG GIT_BRANCH=unknown
ARG GIT_COMMIT_ID_ABBREV=unknown

# system libraries
# Try to only install system libraries you actually need
# Package Manager is a good resource to help discover system deps
RUN apt-get update && \
    apt-get install -y python3-pip && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# install required R packages - fail the build if there are any missing dependencies
RUN R -e ' \
  install.packages(c("remotes", "rJava", "dplyr", "DatabaseConnector", "ggplot2", "plotly", "shinyWidgets", "shiny", "stringi"), repos="http://cran.rstudio.com/"); \
  pkgs <- c("remotes", "rJava", "dplyr", "DatabaseConnector", "ggplot2", "plotly", "shinyWidgets", "shiny", "stringi"); \
  sapply(pkgs, function(pkg) { \
    if (!require(pkg, character.only = TRUE, quietly = TRUE)) { \
      stop(paste("Package", pkg, "failed to load")) \
    } \
  })'

RUN R CMD javareconf

# Set workdir and copy app files
WORKDIR /srv/shiny-server/${APP_NAME}

# copy the app directory into the image
COPY ./app.R .

# install additional R packages and fail the build if there are any missing dependencies
# temporarily install shiny@rc-v1.11.1 hot fix for shiny v1.11.0 bug
RUN --mount=type=secret,id=build_github_pat \
    cp /usr/local/lib/R/etc/Renviron /tmp/Renviron && \
    echo "GITHUB_PAT=$(cat /run/secrets/build_github_pat)" >> /usr/local/lib/R/etc/Renviron && \
    R -e "remotes::install_github('OHDSI/ResultModelManager'); if (!require('ResultModelManager', quietly = TRUE)) stop('Installation of ResultModelManager failed')" && \
    R -e "remotes::install_github('OHDSI/OhdsiReportGenerator'); if (!require('OhdsiReportGenerator', quietly = TRUE)) stop('Installation of OhdsiReportGenerator failed')" && \   
    R -e "remotes::install_github('OHDSI/OhdsiShinyModules'); if (!require('OhdsiShinyModules', quietly = TRUE)) stop('Installation of OhdsiShinyModules failed')" && \
    R -e "remotes::install_github('OHDSI/OhdsiShinyAppBuilder'); if (!require('OhdsiShinyAppBuilder', quietly = TRUE)) stop('Installation of OhdsiShinyAppBuilder failed')" && \
    R -e "remotes::install_github('rstudio/shiny@rc-v1.11.1'); if (!require('shiny', quietly = TRUE)) stop('Installation of shiny rc-v1.11.1  failed')" && \
    cp /tmp/Renviron /usr/local/lib/R/etc/Renviron

ENV DATABASECONNECTOR_JAR_FOLDER /root
RUN R -e "DatabaseConnector::downloadJdbcDrivers('postgresql', pathToDriver='/root')"

# run app
EXPOSE 3838
CMD R -e "shiny::runApp('./', host = '0.0.0.0', port = 3838)"
