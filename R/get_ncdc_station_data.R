#' Get met station data from NCDC
#' @description Obtain one or more years of meteorological data for a station from the NCDC hourly global meteorology archive.
#' @param station_id a station identifier composed of the station's USAF and WBAN numbers, separated by a hyphen.
#' @param startyear the starting year for the collected data.
#' @param endyear the ending year for the collected data.
#' @import lubridate
#' @import plyr
#' @import downloader
#' @export get_ncdc_station_data

get_ncdc_station_data <- function(station_id,
                                  startyear,
                                  endyear){
  # Add require statements
  library(lubridate)
  library(plyr)
  library(downloader)
  
  if (is.null(startyear) | is.null(endyear)) {
    stop("Please enter starting and ending years for surface station data")
  }
  # Check whether 'startyear' and 'endyear' are both numeric
  if (!is.numeric(startyear) | !is.numeric(endyear)) {
    stop("Please enter numeric values for the starting and ending years")
  }
  # Check whether 'startyear' and 'endyear' are in the correct order
  if (startyear > endyear) {
    stop("Please enter the starting and ending years in the correct order")
  }
  # Check whether 'staryear' and 'endyear' are within set bounds
  if (startyear < 1892 | endyear < 1892 | 
      startyear > year(Sys.Date()) | endyear > year(Sys.Date())) {
    stop("Please enter the starting and ending years in the correct order")
  }
  
  # Get hourly surface data history CSV from NOAA/NCDC FTP
  file <- "ftp://ftp.ncdc.noaa.gov/pub/data/noaa/isd-history.csv"
  
  repeat {
    try(download(file, "isd-history.csv", quiet = TRUE))
    if (file.info("isd-history.csv")$size > 0) { break }
  }
  
  # Read in the "isd-history" CSV file
  st <- read.csv("isd-history.csv")
  
  # Get formatted list of station names and elevations
  names(st)[c(3, 9)] <- c("NAME", "ELEV")
  st <- st[, -6]
  
  # Recompose the years from the data file
  st$BEGIN <- as.numeric(substr(st$BEGIN, 1, 4))
  st$END <- as.numeric(substr(st$END, 1, 4))
  
  # Generate a list based on the domain location, also ignoring stations without
  # beginning years reported
  target_station <- 
    subset(st, 
           st$USAF == as.numeric(unlist(strsplit(station_id, "-"))[1]) &
             st$WBAN == as.numeric(unlist(strsplit(station_id, "-"))[2]))
  
  tz_offset <-
    get_tz_offset(target_station$LON[1], target_station$LAT[1])
  
  # if tz_offset is positive, then also download year of data previous to
  # beginning of series
  if (tz_offset > 0) startyear <- startyear - 1
  
  # if tz_offset is negative, then also download year of data following the
  # end of series
  if (tz_offset < 0) endyear <- endyear + 1
  
  
  # Download the gzip-compressed data files for the years specified
  data_files_downloaded <- vector(mode = "character")
  
  for (i in startyear:endyear){
    
    station_required_year <- 
      target_station[target_station$BEGIN <= i &
                       target_station$END >= i, ]
    
    if (nrow(station_required_year) > 0){
      
      data_file_to_download <- 
        paste0(sprintf("%06d", station_required_year[1,1]),
               "-", sprintf("%05d", station_required_year[1,2]),
               "-", i, ".gz")
      
      download(url = paste0("ftp://ftp.ncdc.noaa.gov/pub/data/noaa/", i,
                            "/", data_file_to_download),
               destfile = data_file_to_download)
      
      data_files_downloaded <- c(data_files_downloaded,
                                 data_file_to_download)
    }
  }
  
  column_widths <- c(4, 6, 5, 4, 2, 2, 2, 2, 1, 6,
                     7, 5, 5, 5, 4, 3, 1, 1, 4, 1,
                     5, 1, 1, 1, 6, 1, 1, 1, 5, 1,
                     5, 1, 5, 1)
  
  for (i in 1:length(data_files_downloaded)){
    
    # Read data from mandatory data section of each file, which is a fixed-width string
    data <- read.fwf(data_files_downloaded[i], column_widths)
    
    # Remove select columns from data frame
    data <- data[, c(2:8, 10:11, 13, 16, 19, 21, 29, 31, 33)]
    
    # Apply new names to the data frame columns
    names(data) <-
      c("usaf_id", "wban", "year", "month", "day", "hour", "minute",
        "lat", "lon", "elev", "wd", "ws", "ceiling_height",
        "temp", "dew_point", "atmos_pres")
    
    #
    # Recompose data and use consistent missing indicators of NA for missing data
    #
    
    # Correct the latitude values
    data$lat <- data$lat/1000
    
    # Correct the longitude values
    data$lon <- data$lon/1000
    
    # Correct the wind direction values
    data$wd <- 
      ifelse(data$wd == 999, NA, data$wd)
    
    # Correct the wind speed values
    data$ws <- 
      ifelse(data$ws == 9999, NA, data$ws/10)
    
    # Correct the wind temperature values
    data$temp <- 
      ifelse(data$temp == 9999, NA, data$temp/10)
    
    # Correct the dew point values
    data$dew_point <- 
      ifelse(data$dew_point == 9999, NA, data$dew_point/10)
    
    # Correct the atmospheric pressure values
    data$atmos_pres <- 
      ifelse(data$atmos_pres == 99999, NA, data$atmos_pres/10)
    
    # Correct the ceiling height values
    data$ceiling_height <- 
      ifelse(data$ceiling_height == 99999, NA, data$ceiling_height)
    
    # Calculate RH values using the August-Roche-Magnus approximation
    for (j in 1:nrow(data)){
      
      if (j == 1) rh <- vector("numeric")
      
      rh_j <- 
        ifelse(is.na(data$temp[j]) | is.na(data$dew_point[j]), NA,
               100 * (exp((17.625 * data$dew_point[j]) /
                            (243.04 + data$dew_point[j]))/
                        exp((17.625 * (data$temp[j])) /
                              (243.04 + (data$temp[j])))))
      
      rh_j <- round_any(as.numeric(rh_j), 0.1, f = round)
      
      rh <- c(rh, rh_j)
    }
    
    data$rh <- rh
    
    # Write CSV file for each station
    write.csv(data,
              file = paste0(gsub(".gz", "", data_files_downloaded[i]),
                            ".csv"), row.names = FALSE)
  }
  
}


