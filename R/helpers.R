# Helperl functions that helps the API wrapper get_wage function

valid_api_key <- function(api_key){
  !is.null(api_key) && is.character(api_key) && nchar(api_key) == 36
}

translate_dataset <- function(dataset){
  dataset <- as.character(dataset)
  translations <- c("2012" = "5fd8d9f2-008f-41a6-a200-1a0253a4d9b5",
                    "2013" = "c4bcd5c4-9b04-4bb8-8067-f5484a69e592",
                    "2014" = "ff3ea4e1-896f-4fa2-8754-c8a9f83c89b0",
                    "2015" = "7215dbfa-8e5c-417c-8c95-0a916eaedcc1",
                    "2016" = "2a1fe964-7d3f-4337-a454-ef346db5609a",
                    "2019" = "3abae67c-78a7-4e06-b2b2-fe9870100381",
                    "2020" = "c2db20d5-92bc-40d2-aa9f-6c868badc0b9",
                    "2021" = "74a2d523-9760-415e-b722-8a237ab649db",
                    "2022" = "8d49f430-6dfd-4122-a18d-b0868381f0e6",
                    "2023" = "ff45366b-1c17-4862-8325-f6e7797c7c56")
  if(dataset %in% names(translations)) dataset = as.character(translations[dataset])
  return(dataset)
}

translate_province <- function(province){
  full_prov_name <- c("BC" = "British Columbia",
                      "AB" = "Alberta",
                      "SK" = "Saskatchewan",
                      "MB" = "Manitoba",
                      "ON" = "Ontario",
                      "QC" = "Quebec",
                      "NB" = "New Brunswick",
                      "YK" = "Yukon Territory",
                      "NU" = "Nunavut",
                      "NL" = "Newfoundland and Labrador",
                      "NS" = "Nova Scotia",
                      "NT" = "Northwest Territories",
                      "NW" = "Northwest Territories",
                      "PE" = "Prince Edward Island",
                      "YT" = "Yukon Territory")

  province <- dplyr::case_when(province %in% names(full_prov_name) ~ full_prov_name[province], TRUE ~ province)
  return(province)
}

get_wage_single_year <- function(year, api_key){
  dataset <- translate_dataset(year)
  req <- httr2::request("https://open.canada.ca/data/en/api/action/datastore_search")
  tryCatch({
    result <- req |>
      httr2::req_headers(Authorization = api_key) |>
      httr2::req_body_json(list(
        resource_id = dataset,
        limit = 45000,
        filters = if(year == 2023){
          list(ER_Name = list("Newfoundland and Labrador", "New Brunswick", "Quebec", "Ontario",
                              "Manitoba", "Alberta", "British Columbia", "Yukon Territory", "Northwest Territories",
                              "Nunavut", "Prince Edward Island", "Saskatchewan", "Nova Scotia"))
        } else if(year == 2014 | year == 2015){
          list(Economic_Region = list("Newfoundland and Labrador", "New Brunswick", "Quebec", "Ontario",
                                      "Manitoba", "Alberta", "British Columbia", "Yukon Territory", "Northwest Territories",
                                      "Nunavut", "Prince Edward Island", "Saskatchewan", "Nova Scotia"))
        } else {
          list(ER_Name_Nom_RE = list("Newfoundland and Labrador", "New Brunswick", "Quebec", "Ontario",
                                     "Manitoba", "Alberta", "British Columbia", "Yukon Territory", "Northwest Territories",
                                     "Nunavut", "Prince Edward Island", "Saskatchewan", "Nova Scotia"))
        }
      )) |>
      httr2::req_perform() |>
      httr2::resp_body_json()
    result <- pre_process_dataset(year, result)
  },
  error = function(e){
    cat("Error in API call:", conditionMessage(e), "\n")
    NULL
  }
  )
}

pre_process_dataset <- function(period, json){
  df <- tibble::as_tibble(do.call(rbind, json$result$records)) |>
    dplyr::rename_all(tolower) |>
    tidyr::unnest((everything())) |>
    dplyr::select(dplyr::contains(c("noc_title", "wage_salaire", "annual")), prov, -dplyr::matches("fra|average|noc_title_f")) |>
    dplyr::mutate(across(dplyr::contains("wage"), as.numeric), year=as.Date(paste0(period, "-01-01"), format = "%Y-%m-%d")) |>
    dplyr::rename(occupation = dplyr::contains("noc_title"),
                  low_wage = low_wage_salaire_minium,
                  median_wage = median_wage_salaire_median,
                  high_wage = high_wage_salaire_maximal,
                  province = prov)
  if(period == 2016){
    df <- df |>
      dplyr::rename(annual_wage_flag = annual_wage) |>
      dplyr::select(-dplyr::matches("salaire_annuel"))
  } else{
    df <- df |>
      dplyr::rename(annual_wage_flag = annual_wage_flag_salaire_annuel)
  }
  if(period != 2012 & period != 2013 & period != 2016){
    df$province <- translate_province(df$province)
  }
  df <- df |>
    dplyr::mutate(across(dplyr::ends_with("wage"), ~ ifelse(annual_wage_flag == 1, ., .*40*52)))
  df
}
