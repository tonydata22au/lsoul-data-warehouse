CREATE TABLE `marine-cycle-484213-b4.google_ads.p_ads_Audience_6757483582`
(
  audience_id STRING OPTIONS(description=" ID of the audience."),
  audience_description STRING OPTIONS(description="Description of this audience."),
  audience_dimensions STRING OPTIONS(description="Positive dimensions specifying the audience composition."),
  audience_exclusion_dimension STRING OPTIONS(description="Negative dimension specifying the audience composition."),
  audience_name STRING OPTIONS(description="Name of the audience. It should be unique across all audiences. It must have a minimum length of 1 and maximum length of 255."),
  audience_status STRING OPTIONS(description="Status of this audience. Indicates whether the audience is enabled or removed.")
)
PARTITION BY DATE(_PARTITIONTIME);
