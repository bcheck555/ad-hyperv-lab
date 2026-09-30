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

  <!-- Expose two virtual NUMA nodes and pin each cell to its matching host node. -->
  <xsl:template match="cpu">
    <cpu mode="host-passthrough" check="none" migratable="off">
      <topology sockets="2" dies="1" cores="${vcpu_per_numa_node}" threads="1"/>
      <numa>
        <cell id="0" cpus="0-${numa0_guest_last}" memory="${numa_cell_memory_kib}" unit="KiB"/>
        <cell id="1" cpus="${numa1_guest_first}-${numa1_guest_last}" memory="${numa_cell_memory_kib}" unit="KiB"/>
      </numa>
    </cpu>
  </xsl:template>

  <xsl:template match="vcpu">
    <xsl:copy>
      <xsl:apply-templates select="@*|node()"/>
    </xsl:copy>
    <cputune>
${vcpu_pins_xml}
    </cputune>
    <numatune>
      <memory mode="strict" nodeset="0-1"/>
      <memnode cellid="0" mode="strict" nodeset="0"/>
      <memnode cellid="1" mode="strict" nodeset="1"/>
    </numatune>
  </xsl:template>

  <!-- Keep the Windows boot disk on the same IDE controller used by Packer.
       Switching the boot controller before viostor is boot-active can hang Windows.
       The high-I/O data disk remains paravirtualized. -->
  <xsl:template match="disk[@device='disk'][1]/target">
    <target dev="hda" bus="ide"/>
  </xsl:template>

  <xsl:template match="disk[@device='disk'][2]/target">
    <target dev="vdb" bus="virtio"/>
  </xsl:template>

  <xsl:template match="disk[@device='disk'][1]/driver">
    <driver name="qemu" type="qcow2" cache="none" io="native" discard="unmap" detect_zeroes="unmap"/>
  </xsl:template>

  <xsl:template match="disk[@device='disk'][2]/driver">
    <driver name="qemu" type="raw" cache="none" io="native"/>
  </xsl:template>

  <!-- Let libvirt assign fresh PCI addresses after changing disk targets. -->
  <xsl:template match="disk[@device='disk']/address"/>

  <!-- Use the NetKVM driver installed by virtio-win. -->
  <xsl:template match="interface/model">
    <model type="virtio"/>
  </xsl:template>

</xsl:stylesheet>
