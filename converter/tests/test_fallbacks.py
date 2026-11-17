"""Fallbacki z Morrowind.ini / openmw.cfg (etap 10): pytania, awans, pogoda, woda, księżyce – klucze jak openmw-iniimporter."""

from mwconv import fallbacks


def test_ini_weather_keys(tmp_path):
    ini = tmp_path / "Morrowind.ini"
    ini.write_bytes(b"[Weather]\r\nSunrise Time=6\r\nSky Pre-Sunset Time=1.5\r\n"
                    b"[Weather Clear]\r\nSky Day Color=095,135,203\r\n"
                    b"[Weather Thunderstorm]\r\nCloud Texture=Tx_Sky_Thunder.dds\r\n"
                    b"[Moons]\r\nMasser Size=94\r\n[Water]\r\nMap Alpha=0.4\r\n[General]\r\nIgnored=1\r\n")
    v = fallbacks._from_ini(ini)
    assert v["Weather_Sunrise_Time"] == "6"
    assert v["Weather_Sky_Pre-Sunset_Time"] == "1.5"
    assert v["Weather_Clear_Sky_Day_Color"] == "095,135,203"
    assert v["Weather_Thunderstorm_Cloud_Texture"] == "Tx_Sky_Thunder.dds"
    assert v["Moons_Masser_Size"] == "94" and v["Water_Map_Alpha"] == "0.4"
    assert not any(k.startswith("General") for k in v)


def test_openmw_cfg_weather(tmp_path):
    cfg = tmp_path / "openmw.cfg"
    cfg.write_text("fallback=Weather_Clear_Sky_Day_Color,095,135,203\nfallback=General_Foo,1\n", encoding="utf-8")
    v = fallbacks._from_openmw_cfg(cfg)
    assert v == {"Weather_Clear_Sky_Day_Color": "095,135,203"}


def test_movies_from_ini_and_cfg(tmp_path):
    """Start gry: [Movies] z Morrowind.ini → Movies_Company_Logo… (jak openmw-iniimporter), też z openmw.cfg."""
    ini = tmp_path / "Morrowind.ini"
    ini.write_bytes(b"[Movies]\r\nCompany Logo=bethesda logo.bik\r\nMorrowind Logo=mw_logo.bik\r\nNew Game=mw_intro.bik\r\n")
    v = fallbacks._from_ini(ini)
    assert v == {"Movies_Company_Logo": "bethesda logo.bik", "Movies_Morrowind_Logo": "mw_logo.bik",
                 "Movies_New_Game": "mw_intro.bik"}
    cfg = tmp_path / "openmw.cfg"
    cfg.write_text("fallback=Movies_New_Game,mw_intro.bik\n", encoding="utf-8")
    assert fallbacks._from_openmw_cfg(cfg) == {"Movies_New_Game": "mw_intro.bik"}
