<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet version="1.0"
  xmlns:xsl="http://www.w3.org/1999/XSL/Transform">

  <xsl:output method="xml" indent="yes"/>

  <!-- Identity transform. -->
  <xsl:template match="@*|node()">
    <xsl:copy>
      <xsl:apply-templates select="@*|node()"/>
    </xsl:copy>
  </xsl:template>

  <!-- Match the Windows system disk to the IDE bus used during the Packer install. -->
  <xsl:template match="disk[@device='disk']/target">
    <target dev="hda" bus="ide"/>
  </xsl:template>

  <!-- Drop provider-generated virtio/Pci disk addresses after converting the disk to IDE. -->
  <xsl:template match="disk[@device='disk']/address"/>

  <!-- Use an inbox Windows-compatible NIC model unless virtio drivers are added to the image. -->
  <xsl:template match="interface/model">
    <model type="e1000"/>
  </xsl:template>

</xsl:stylesheet>
