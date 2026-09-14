from os import environ

from vendor.nc_py_api import cpa_logger

logger = cpa_logger.getChild("mediadc")
logger.setLevel(level=environ.get("LOGLEVEL", "INFO").upper())
