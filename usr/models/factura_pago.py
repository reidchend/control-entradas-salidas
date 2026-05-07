from sqlalchemy import Column, Integer, String, Float, DateTime, ForeignKey
from sqlalchemy.sql import func
from sqlalchemy.orm import relationship
from usr.database.base import Base


class FacturaPago(Base):
    __tablename__ = "factura_pagos"
    __table_args__ = {'extend_existing': True}
    
    id = Column(Integer, primary_key=True, index=True)
    factura_id = Column(Integer, ForeignKey("facturas.id"), nullable=False)
    tipo_pago = Column(String(50), nullable=False, comment="efectivo, transferencia, divisas")
    monto = Column(Float, nullable=False)
    referencia = Column(String(100), nullable=True)
    tasa_cambio = Column(Float, nullable=True, comment="Tasa de cambio utilizada (solo para divisas)")
    fecha_pago = Column(DateTime(timezone=True), server_default=func.now())
    
    # Relación con factura
    factura = relationship("Factura", back_populates="pagos")
    
    def __repr__(self):
        return f"<FacturaPago(factura_id={self.factura_id}, tipo='{self.tipo_pago}', monto={self.monto})>"