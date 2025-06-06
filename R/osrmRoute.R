#' @name osrmRoute
#' @title Get the Shortest Path Between Two Points
#' @description Build and send an OSRM API query to get the travel geometry
#' between two points. This function interfaces with the \emph{route} OSRM
#' service.\cr
#' Use \code{src} and \code{dst} to get the shortest direct route between
#' two points.\cr
#' Use \code{loc} to get the shortest route between two points using
#' ordered waypoints.
#'
#'
#' @param src starting point of the route.
#' \code{src} can be: \itemize{
#'   \item a vector of coordinates (longitude and latitude, WGS 84),
#'   \item a data.frame of longitudes and latitudes (WGS 84),
#'   \item a matrix of longitudes and latitudes (WGS 84),
#'   \item an sfc object of type POINT,
#'   \item an sf object of type POINT.
#' }
#' If relevant, row names are used as identifiers.\cr
#' If \code{src} is a data.frame, a matrix, an sfc object or an sf object then
#' only the first row or element is considered.
#' @param dst destination of the route.
#' \code{dst} can be: \itemize{
#'   \item a vector of coordinates (longitude and latitude, WGS 84),
#'   \item a data.frame of longitudes and latitudes (WGS 84),
#'   \item a matrix of longitudes and latitudes (WGS 84),
#'   \item an sfc object of type POINT,
#'   \item an sf object of type POINT.
#' }
#' If relevant, row names are used as identifiers.\cr
#' If \code{dst} is a data.frame, a matrix, an sfc object or an sf object then
#' only the first row or element is considered.
#'
#' @param loc starting point, waypoints (optional) and destination of the
#' route. \code{loc} can be: \itemize{
#'   \item a data.frame of longitudes and latitudes (WGS 84),
#'   \item a matrix of longitudes and latitudes (WGS 84),
#'   \item an sfc object of type POINT,
#'   \item an sf object of type POINT.
#' }
#' The first row or element is the starting point then waypoints are used in
#' the order they are stored in \code{loc} and the last row or element is
#' the destination.\cr
#' If relevant, row names are used as identifiers.\cr
#' @param overview "full", "simplified" or FALSE. Use "full" to return the
#' detailed geometry, use "simplified" to return a simplified geometry, use
#' FALSE to return only time and distance.
#' @param exclude pass an optional "exclude" request option to the OSRM API.
#' @param osrm.server the base URL of the routing server.
#' @param osrm.profile the routing profile to use, e.g. "car", "bike" or "foot".
#' @param annotations Flag whether to return detailed route metadata. Currently
#' only returns all nodes of a route
#' @return
#' The output of this function is a list of length two. The first element is an sf LINESTRING of the shortest route.\cr
#' It contains 4 fields: \itemize{
#'   \item starting point identifier
#'   \item destination identifier
#'   \item travel time in minutes
#'   \item travel distance in kilometers.
#'   }
#' If src (or loc) is a vector, a data.frame or a matrix, the coordinate
#' reference system (CRS) of the route is EPSG:4326 (WGS84).\cr
#' If src (or loc) is an sfc or sf object, the route has the same CRS
#' as src (or loc).\cr\cr
#' If overview is FALSE, a named numeric vector is returned. It contains travel
#' time (in minutes) and travel distance (in kilometers).\cr
#' The second list element is a character vector of all nodes of the route (if 
#' the \code{annotations} parameter is set to TRUE)
#' @importFrom sf st_as_sfc st_crs st_geometry st_sf st_as_sf st_transform
#' @examples
#' \dontrun{
#' library(sf)
#' apotheke.df <- read.csv(system.file("csv/apotheke.csv", package = "osrm"))
#' apotheke.sf <- st_read(system.file("gpkg/apotheke.gpkg", package = "osrm"),
#'   quiet = TRUE
#' )
#' # Travel path between points
#' route1 <- osrmRoute(src = apotheke.sf[1, ], dst = apotheke.sf[16, ])
#' # Display paths
#' plot(st_geometry(route1))
#' plot(st_geometry(apotheke.sf[c(1, 16), ]), col = "red", pch = 20, add = TRUE)
#'
#' # Return only duration and distance
#' route3 <- osrmRoute(
#'   src = apotheke.df[1, c("lon", "lat")],
#'   dst = apotheke.df[16, c("lon", "lat")],
#'   overview = FALSE
#' )
#' route3
#'
#' # Using only coordinates
#' route4 <- osrmRoute(
#'   src = c(13.412, 52.502),
#'   dst = c(13.454, 52.592)
#' )
#' plot(st_geometry(route4))
#'
#' # Using via points
#' route5 <- osrmRoute(loc = apotheke.sf[c(1, 2, 4, 3), ])
#' plot(st_geometry(route5), col = "red", lwd = 2)
#' plot(st_geometry(apotheke.sf[c(1, 2, 4, 3), ]), add = TRUE)
#'
#' # Using a different routing server
#' u <- "https://routing.openstreetmap.de/routed-foot/"
#' route5 <- osrmRoute(apotheke.sf[1, ], apotheke.sf[16, ], osrm.server = u)
#' route5
#'
#' # Using an open routing service with support for multiple modes
#' # see https://github.com/riatelab/osrm/issues/67
#' u <- "https://routing.openstreetmap.de/"
#' options(osrm.server = u)
#' route6 <- osrmRoute(apotheke.sf[1, ], apotheke.sf[16, ],
#'   osrm.profile = "bike"
#' )
#' route7 <- osrmRoute(apotheke.sf[1, ], apotheke.sf[16, ],
#'   osrm.profile = "car"
#' )
#' plot(st_geometry(route7), col = "green") # car
#' plot(st_geometry(route6), add = TRUE) # bike
#' plot(st_geometry(route5), col = "red", add = TRUE) # foot
#' }
#' @export
osrmRoute <- function(src,
                      dst,
                      loc,
                      annotations = FALSE,
                      overview = "simplified",
                      exclude,
                      osrm.server = getOption("osrm.server"),
                      osrm.profile = getOption("osrm.profile")) {
  opt <- options(error = NULL)
  on.exit(options(opt), add = TRUE)

  url <- base_url(osrm.server, osrm.profile, "route")

  if (missing(loc)) {
    # From src to dst
    src <- input_route(x = src, id = "src", single = TRUE)
    dst <- input_route(x = dst, id = "dst", single = TRUE)
    id1 <- src$id
    id2 <- dst$id
    oprj <- src$oprj
    coords <- paste0(src$lon, ",", src$lat, ";", dst$lon, ",", dst$lat)
  } else {
    # from src to dst via x, y, z... (data.frame or sf input)
    loc <- input_route(x = loc, single = FALSE)
    oprj <- loc$oprj
    id1 <- loc$id1
    id2 <- loc$id2
    coords <- paste0(
      apply(cbind(loc$lon, loc$lat), MARGIN = 1, FUN = paste0, collapse = ","),
      collapse = ";"
    )
  }

  url <- paste0(
    url,
    coords,
    "?alternatives=false&annotations=",
    ifelse(annotations == FALSE, "false", "true"),
    "&geometries=polyline&steps=false&overview=",
    tolower(overview),
    "&generate_hints=false"
  )

  # adding exclude parameter
  if (!missing(exclude)) {
    url <- paste0(url, "&exclude=", exclude)
  }

  e <- try(
    {
      req_handle <- curl::new_handle(verbose = FALSE)
      curl::handle_setopt(req_handle, useragent = "osrm_R_package")
      r <- curl::curl_fetch_memory(utils::URLencode(url), handle = req_handle)
    },
    silent = TRUE
  )
  if (inherits(e, "try-error")) {
    stop(e, call. = FALSE)
  }

  # test result validity
  test_http_error(r)
  res <- RcppSimdJson::fparse(rawToChar(r$content))

  if (overview == FALSE) {
    return(round(c(
      duration = res$routes$duration / 60,
      distance = res$routes$distance / 1000
    ), 2))
  }
  # Nodes of the route
  nodes <- res$routes$legs[[1]]$annotation[[1]]$nodes
  print(nodes)
  
  # Coordinates of the line
  geodf <- googlePolylines::decode(res$routes$geometry)[[1]][, c(2, 1)]
  # Convert to LINESTRING
  rcoords <- paste0(geodf$lon, " ", geodf$lat, collapse = ", ")
  rosf <- st_sf(
    src = id1, dst = id2,
    duration = res$routes$duration / 60,
    distance = res$routes$distance / 1000,
    geometry = st_as_sfc(paste0("LINESTRING(", rcoords, ")")),
    crs = 4326,
    row.names = paste(id1, id2, sep = "_")
  )
  # prj
  if (!is.na(oprj)) {
    rosf <- st_transform(rosf, oprj)
  }

  return(list(rosf, nodes))
}
